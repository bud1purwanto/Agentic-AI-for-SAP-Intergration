# MCP SQL — Konektor SQL Server Dinamis

**Status:** Disetujui
**Tanggal:** 2026-07-17
**Lokasi implementasi:** `MCP SQL/` (root proyek, flat — mengikuti pola `MCP Email`, bukan `MCP SAP/sap-leader-mcp` yang nested)

## Latar Belakang

Pengguna sudah punya MCP SAP (RFC ke SAP ECC), RAG SAP, dan MCP Email. Sekarang dibutuhkan MCP baru untuk konek ke SQL Server internal perusahaan, dengan dua kebutuhan utama:

1. Server dan database harus bisa ditambah lewat config (`.json`/`.env`), tanpa membuat MCP baru atau mengubah kode setiap kali ada server/database baru.
2. Rencana ke depan: dibagikan ke coworker (lewat HTTP), bukan hanya dipakai sendiri secara lokal (stdio).

Referensi arsitektur: `MCP SAP/sap-leader-mcp` — pemisahan `tool-registry.js` (definisi tool) dari transport (`index.js` stdio / `http-server.js` HTTP), dan `server-manager.js` sebagai pengelola config + koneksi.

## Cakupan

- **Read-only.** Tidak ada INSERT/UPDATE/DELETE/DDL/EXEC. Ditegakkan oleh validator query DAN (idealnya) oleh permission SQL Server login itu sendiri (`db_datareader`).
- **Multi-server, multi-database, dinamis** lewat config — menambah server baru = edit `config/sql-servers.json` + 1 baris `.env`, tanpa sentuh kode.
- **Transport ganda**: stdio untuk pemakaian lokal sekarang, HTTP untuk dibagikan ke coworker nanti. Tool ditulis sekali di `tool-registry.js`, dipakai oleh keduanya.
- Autentikasi ke SQL Server: **SQL Server Authentication** saja (sesuai setup existing — user `DEVELOPER` dkk).

Di luar cakupan (tidak dikerjakan versi ini): write access, Windows Authentication, multi-user auth token untuk HTTP (dibahas lagi saat HTTP benar-benar diaktifkan).

## Konfigurasi

### `config/sql-servers.json` (aman di-commit, tanpa password)

```json
{
  "default_server": "dev-224",
  "default_query_timeout_ms": 30000,
  "default_max_rows": 1000,
  "servers": [
    {
      "name": "dev-224",
      "host": "192.168.1.224",
      "port": 1433,
      "environment": "development",
      "aliases": ["dev", "developer"],
      "user": "DEVELOPER",
      "password_env": "SQL_PWD_DEV_224",
      "encrypt": false,
      "trust_server_certificate": true,
      "allowed_databases": null
    }
  ]
}
```

- `password_env` menunjuk ke nama variabel di `.env` — password sendiri tidak pernah ada di file JSON.
- `allowed_databases: null` berarti semua database yang terlihat oleh user login akan ditampilkan; diisi array string untuk membatasi.
- `encrypt` / `trust_server_certificate` eksplisit per-server karena default driver `mssql` (`encrypt: true`) akan gagal connect ke server internal yang belum pakai TLS/certificate resmi (sesuai screenshot: Encrypt=Optional, Trust Server Certificate tidak dicentang).

### `.env` (gitignored)

```
SQL_PWD_DEV_224=...
```

Menambah server baru: tambah satu blok di `sql-servers.json` + satu baris `.env`. Tidak ada perubahan kode.

## Arsitektur

```
MCP SQL/
  .env                       (gitignored)
  .env.example
  .gitignore
  package.json
  config/
    sql-servers.json
  src/
    server-manager.js        # load config, resolve server ref, cache connection pool per server+database
    tool-registry.js         # daftar tool + schema, dipakai stdio & HTTP
    utils/
      sql-client.js          # wrapper mssql: connect, query dengan TOP-N injection, timeout
      query-validator.js     # penegak read-only (parsing teks SQL)
    tools/
      server-tools.js        # list_servers, set_active_server, list_databases
      query-tools.js         # run_query
      schema-tools.js        # list_tables, describe_table, search_objects, get_object_definition, explain_query
  index.js                   # entry point stdio
  http-server.js             # entry point HTTP (untuk dibagikan ke coworker)
```

### Manajemen koneksi & sesi

- `server-manager.js` memegang **cache pool koneksi** ber-key `server+database` (bukan buka-tutup pool setiap ganti server seperti di MCP SAP) — karena `mssql` sudah mendukung pooling dan satu sesi analisa biasa bolak-balik antar database di server yang sama.
- **Server aktif disimpan per sesi** (objek konteks `ctx` yang diteruskan ke setiap handler tool), bukan di satu variabel global seperti `sap-leader-mcp`. Di stdio hanya ada satu sesi sehingga perilakunya identik dengan MCP SAP (`set_active_server` lalu tool lain otomatis pakai server itu). Begitu HTTP diaktifkan untuk multi-coworker, pemilihan server tidak bocor antar user. Cache pool koneksi tetap dibagi lintas sesi; yang di-per-sesi-kan hanya *pilihan* server aktif.
- Semua tool juga menerima parameter `server` dan `database` opsional untuk override sekali jalan tanpa mengubah server aktif sesi.

## Daftar Tool

**Manajemen server**
- `list_servers()` — semua server dari config + host, environment, alias, status aktif. Tanpa password.
- `set_active_server(server_ref)` — pilih server aktif (nama/nomor/alias/IP). Langsung tes koneksi agar kredensial salah ketahuan saat itu juga.
- `list_databases()` — dari `sys.databases`, dihormati `allowed_databases` bila diisi.

**Query**
- `run_query(sql, server?, database?, max_rows?, timeout_ms?)` — jalankan SELECT. Default `max_rows`=1000, `timeout_ms`=30000 (dari config, bisa dinaikkan per panggilan). `max_rows` diterapkan lewat `TOP N` di sisi query, bukan memotong hasil setelah ditarik penuh. Respons: `{ rows, row_count, columns, truncated, server, database, elapsed_ms }`.

**Eksplorasi schema**
- `list_tables(schema?)` — tabel & view dari `INFORMATION_SCHEMA.TABLES` + estimasi jumlah baris dari `sys.dm_db_partition_stats`.
- `describe_table(table)` — kolom, tipe, nullability, PK, FK, index.
- `search_objects(pattern, type?)` — cari tabel/view/kolom/stored procedure berdasar pattern nama (`sys.objects`, `sys.columns`).
- `get_object_definition(object_name)` — source T-SQL view/procedure/function via `sys.sql_modules`.
- `explain_query(sql)` — estimated execution plan (`SET SHOWPLAN_XML ON`), tanpa eksekusi. Jika login tidak punya izin `SHOWPLAN`, kembalikan pesan jelas, bukan error mentah.

## Penegakan Read-Only

Lapisan pertama: `query-validator.js` dijalankan sebelum eksekusi apa pun di `run_query`:
1. Strip komentar (`--`, `/* */`) agar tidak dipakai menyelundupkan statement.
2. Tolak jika statement pertama bukan `SELECT`/`WITH`.
3. Tolak jika ada multi-statement (dipisah `;` lalu ada isi lain).
4. Tolak jika mengandung kata kunci mutasi: `INSERT`, `UPDATE`, `DELETE`, `MERGE`, `DROP`, `ALTER`, `TRUNCATE`, `EXEC`, `INTO`.

Batasan yang disadari: validasi berbasis parsing teks tidak bisa 100% menutup semua celah T-SQL. Karena itu lapisan kedua — **dan yang sesungguhnya menjamin** — adalah login SQL Server yang dipakai MCP ini seharusnya hanya berperan `db_datareader`. Ini krusial terutama begitu HTTP dibuka ke coworker; jika login `DEVELOPER` saat ini punya hak tulis, direkomendasikan dibuatkan login read-only khusus.

## Alur Data — `run_query`

1. Terima `sql`, `server?`, `database?`, `max_rows?`, `timeout_ms?`.
2. Resolve server: override → server aktif sesi → error "panggil set_active_server dulu" jika tidak ada keduanya.
3. Validator read-only jalan di teks SQL; gagal → error terstruktur dengan alasan spesifik, tanpa menyentuh jaringan.
4. Ambil/reuse pool koneksi `server+database` dari cache.
5. Eksekusi dengan `timeout_ms`, `TOP N` diterapkan di query.
6. Kembalikan hasil terstruktur seperti di atas.

## Penanganan Error

Selalu object JSON terstruktur, tidak pernah stack trace mentah:
- Kredensial salah / server tak terjangkau → pesan + saran (cek `.env`, cek jaringan/VPN), `connected: false`.
- Query ditolak validator → `{ error, rejected_reason }` sebelum ke jaringan.
- Timeout → `{ error: "Query timeout setelah Nms", suggestion: "Tambahkan filter WHERE atau naikkan timeout_ms" }`.
- Error T-SQL asli (nama kolom salah, dst.) diteruskan apa adanya — informasi ini dibutuhkan Claude untuk memperbaiki query sendiri.
- Server `environment: "production"` → warning ditempel di setiap respons (mengikuti pola `productionFlag()` MCP SAP), tanpa gating konfirmasi tambahan karena semuanya read-only.

Tool eksplorasi schema (`describe_table`, dll.) tidak melalui validator read-only (bukan SQL bebas dari user) tapi tetap lewat resolusi server & cache pool yang sama.

## Testing

- Unit test murni untuk `query-validator.js`: daftar contoh SQL yang harus lolos vs ditolak, tanpa koneksi database apa pun.
- Verifikasi manual tool-tool yang menyentuh SQL Server terhadap salah satu server nyata (192.168.1.224, user `DEVELOPER`) setelah build selesai, sebelum dianggap kelar.

## Package

- `package.json`: `"type": "module"`, dependency `@modelcontextprotocol/sdk` + `mssql`, script `start` (stdio) dan `start:http` (HTTP) — mengikuti pola `sap-leader-mcp`.
- Dibangun langsung di `MCP SQL/` (flat), bukan nested seperti `sap-leader-mcp`.

## Rencana Setelah Ini

HTTP multi-user auth (token per coworker) dan opsi write-per-database sengaja tidak dirancang detail di sini — akan dibahas terpisah saat siap mengaktifkan HTTP untuk dibagikan.
