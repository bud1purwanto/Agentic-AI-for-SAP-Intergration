*&---------------------------------------------------------------*
*& Report  ZMMI_PO_RELEASE  (v10 - test mode 100% aman, tanpa BAPI)
*&---------------------------------------------------------------*
*& Tujuan : Auto-release PO dengan nilai < USD 500 lewat BAPI_
*&          PO_RELEASE standar. HANYA itu (Sprint 1 scope).
*&---------------------------------------------------------------*

REPORT ZMMI_PO_RELEASE.

TABLES: EKKO, EKPO.

*----------------------------------------------------------------*
* Types & Data
*----------------------------------------------------------------*
TYPES: BEGIN OF TY_EKKO,
         EBELN TYPE EKKO-EBELN,
         BUKRS TYPE EKKO-BUKRS,
         EKORG TYPE EKKO-EKORG,
         EKGRP TYPE EKKO-EKGRP,
         BSART TYPE EKKO-BSART,
         FRGRL TYPE EKKO-FRGRL,
         FRGGR TYPE EKKO-FRGGR,
         FRGSX TYPE EKKO-FRGSX,
         WAERS TYPE EKKO-WAERS,
         BEDAT TYPE EKKO-BEDAT,
         LOEKZ TYPE EKKO-LOEKZ,
       END OF TY_EKKO.

TYPES: BEGIN OF TY_RELCODE,
         FRGCO TYPE T16FV-FRGCO,
       END OF TY_RELCODE.

TYPES: BEGIN OF TY_RESULT,
         EBELN    TYPE EKKO-EBELN,
         NETWR    TYPE EKPO-NETWR,
         USDVAL   TYPE P DECIMALS 2,
         REL_CODE TYPE BAPIMMPARA-PO_REL_COD,
         STATUS   TYPE CHAR1,
         MESSAGE  TYPE BAPI_MSG,
       END OF TY_RESULT.

DATA: LT_EKKO    TYPE STANDARD TABLE OF TY_EKKO,
      LS_EKKO    TYPE TY_EKKO,
      LT_RELCODE TYPE STANDARD TABLE OF TY_RELCODE,
      LS_RELCODE TYPE TY_RELCODE,
      LT_RESULT  TYPE STANDARD TABLE OF TY_RESULT,
      LS_RESULT  TYPE TY_RESULT.

DATA: LV_NETWR          TYPE EKPO-NETWR,
      LV_REAL_NETWR     TYPE BAPICURR-BAPICURR,
      LV_USDVAL         TYPE P DECIMALS 2,
      LV_KURS           TYPE RKB1K-EXCHR,
      LV_RELSTATUS      TYPE BAPIMMPARA-REL_STATUS,
      LV_RELIND         TYPE BAPIMMPARA-PO_REL_IND,
      LV_RETCODE        TYPE SY-SUBRC,
      LV_RELEASED       TYPE CHAR1,
      LV_LINES          TYPE I,
      LV_THRESHOLD_VAL  TYPE ZMAP_TYPE-VALUE,
      LV_THRESHOLD_USD  TYPE P DECIMALS 2.

DATA: LT_RETURN TYPE STANDARD TABLE OF BAPIRETURN,
      LS_RETURN TYPE BAPIRETURN.

*----------------------------------------------------------------*
* Selection Screen
*----------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK B1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS: S_BUKRS FOR EKKO-BUKRS,
                S_EKORG FOR EKKO-EKORG,
                S_EKGRP FOR EKKO-EKGRP,
                S_BSART FOR EKKO-BSART,
                S_EBELN FOR EKKO-EBELN.
SELECTION-SCREEN END OF BLOCK B1.

SELECTION-SCREEN BEGIN OF BLOCK B2 WITH FRAME TITLE TEXT-002.
PARAMETERS: P_TEST TYPE C AS CHECKBOX DEFAULT 'X'.
SELECTION-SCREEN END OF BLOCK B2.

*----------------------------------------------------------------*
START-OF-SELECTION.

*----------------------------------------------------------------*
* 1. Baca threshold auto-release (SATU baris, TEXT1='X') dari ZMAP_TYPE
*----------------------------------------------------------------*
  CLEAR: LV_THRESHOLD_VAL, LV_THRESHOLD_USD.
  SELECT SINGLE VALUE INTO LV_THRESHOLD_VAL
    FROM ZMAP_TYPE
    WHERE PROG = SY-CPROG
      AND TYPE = 'THRESHOLD'
      AND TEXT1 = 'X'
      AND DELETION = SPACE.

  IF SY-SUBRC NE 0.
    WRITE: / 'Mapping THRESHOLD auto-release (TEXT1=X) belum ada di ZMAP_TYPE. Program dihentikan.'.
    EXIT.
  ENDIF.

  LV_THRESHOLD_USD = LV_THRESHOLD_VAL.

*----------------------------------------------------------------*
* 2. Ambil PO yang masih PENDING RELEASE (FRGRL = 'X')
*    -> pakai index EKKO~2 (FRGRL, FRGGR, FRGSX), bukan full scan.
*    -> PO yang sudah release (FRGRL space) otomatis TIDAK ke-select.
*    -> S_EBELN opsional, utk targetkan 1 PO spesifik saat testing.
*----------------------------------------------------------------*
  REFRESH LT_EKKO.
  SELECT EBELN BUKRS EKORG EKGRP BSART FRGRL FRGGR FRGSX WAERS BEDAT LOEKZ
    INTO TABLE LT_EKKO
    FROM EKKO
    WHERE FRGRL EQ 'X'
      AND BUKRS IN S_BUKRS
      AND EKORG IN S_EKORG
      AND EKGRP IN S_EKGRP
      AND BSART IN S_BSART
      AND EBELN IN S_EBELN
      AND BSTYP EQ 'F'
      AND LOEKZ EQ SPACE.

  IF LT_EKKO IS INITIAL.
    WRITE: / 'Tidak ada PO yang perlu diproses sesuai kriteria seleksi.'.
    EXIT.
  ENDIF.

  SORT LT_EKKO BY EBELN.

*----------------------------------------------------------------*
* 3. Proses tiap PO
*----------------------------------------------------------------*
  LOOP AT LT_EKKO INTO LS_EKKO.

    CLEAR: LS_RESULT, LV_NETWR, LV_USDVAL, LV_RELEASED.
    LS_RESULT-EBELN = LS_EKKO-EBELN.

*   --- 3a. Total nilai PO ---
    SELECT SUM( NETWR ) INTO LV_NETWR
      FROM EKPO
      WHERE EBELN = LS_EKKO-EBELN
        AND LOEKZ EQ SPACE.

    LS_RESULT-NETWR = LV_NETWR.

*   --- 3b. Konversi ke USD, pakai KURS PADA TANGGAL PO DIBUAT (BEDAT) ---
*       BUKAN sy-datum (tanggal job jalan). Ini fix Critical #2.
    IF LS_EKKO-WAERS EQ 'USD'.
      LV_USDVAL = LV_NETWR.
    ELSE.
      CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_EXTERNAL'
        EXPORTING
          CURRENCY        = LS_EKKO-WAERS
          AMOUNT_INTERNAL = LV_NETWR
        IMPORTING
          AMOUNT_EXTERNAL = LV_REAL_NETWR.

      CLEAR LV_KURS.
      CALL FUNCTION 'RKC_SINGLE_EXCHANGE_RATE_GET'
        EXPORTING
          DATUM         = LS_EKKO-BEDAT
          KURST         = 'M'
          NCURR         = 'USD'
          VCURR         = LS_EKKO-WAERS
        IMPORTING
          EXCHR         = LV_KURS
        EXCEPTIONS
          NO_RATE_FOUND = 1
          OTHERS        = 2.

      IF SY-SUBRC NE 0.
        LS_RESULT-STATUS  = 'E'.
        LS_RESULT-MESSAGE = 'Kurs (TCURR, KURST=M) pada tanggal PO (BEDAT) tidak ditemukan -- skip, wajib manual'.
        APPEND LS_RESULT TO LT_RESULT.
        CONTINUE.
      ENDIF.

      LV_USDVAL = LV_REAL_NETWR * LV_KURS.
    ENDIF.

    LS_RESULT-USDVAL = LV_USDVAL.

*   --- 3c. Cek scope Sprint 1: HANYA proses kalau nilai < threshold auto ---
    IF LV_USDVAL > LV_THRESHOLD_USD.
      LS_RESULT-STATUS  = 'M'.
      LS_RESULT-MESSAGE = 'Di luar scope Sprint 1 (nilai >= threshold auto-release). Approval routing & notifikasi ditangani di Sprint 2.'.
      APPEND LS_RESULT TO LT_RESULT.
      CONTINUE.
    ENDIF.

*   --- 3d. Cari kandidat release code (T16FV) ---
    REFRESH LT_RELCODE.
    SELECT FRGCO
      INTO TABLE LT_RELCODE
      FROM T16FV
      WHERE FRGGR = LS_EKKO-FRGGR
        AND FRGSX = LS_EKKO-FRGSX.

    IF LT_RELCODE IS INITIAL.
      LS_RESULT-STATUS  = 'W'.
      LS_RESULT-MESSAGE = 'Dalam scope Sprint 1 tapi kombinasi FRGGR/FRGSX tidak ditemukan di T16FV'.
      APPEND LS_RESULT TO LT_RESULT.
      CONTINUE.
    ENDIF.

    LOOP AT LT_RELCODE INTO LS_RELCODE.

*     --- 3e. TEST MODE (v10): TIDAK panggil BAPI_PO_RELEASE sama sekali ---
*         Rollback TERBUKTI tidak bisa membatalkan efek BAPI ini.
*         Simulasi murni: laporkan kode yang akan dipakai, EXIT.
      IF P_TEST EQ 'X'.
        LS_RESULT-REL_CODE = LS_RELCODE-FRGCO.
        LS_RESULT-STATUS   = 'S'.
        LS_RESULT-MESSAGE  = 'Simulasi OK (Test Mode) -- BAPI_PO_RELEASE TIDAK dipanggil, PO tidak tersentuh'.
        LV_RELEASED = 'X'.
        EXIT.
      ENDIF.

      CLEAR: LV_RELSTATUS, LV_RELIND.
      REFRESH LT_RETURN.

      CALL FUNCTION 'BAPI_PO_RELEASE'
        EXPORTING
          PURCHASEORDER     = LS_EKKO-EBELN
          PO_REL_CODE       = LS_RELCODE-FRGCO
          USE_EXCEPTIONS    = 'X'
          NO_COMMIT         = 'X'
        IMPORTING
          REL_STATUS_NEW    = LV_RELSTATUS
          REL_INDICATOR_NEW = LV_RELIND
        TABLES
          RETURN            = LT_RETURN
        EXCEPTIONS
          AUTHORITY_CHECK_FAIL    = 1
          DOCUMENT_NOT_FOUND      = 2
          ENQUEUE_FAIL            = 3
          PREREQUISITE_FAIL       = 4
          RELEASE_ALREADY_POSTED  = 5
          RESPONSIBILITY_FAIL     = 6
          OTHERS                  = 7.

      LV_RETCODE = SY-SUBRC.   " simpan SEGERA

      IF LV_RETCODE EQ 0.
        " --- START FIX UPDATE TERMINATED ---
        " Cek apakah ada error (E) atau abort (A) di tabel RETURN dari BAPI
        READ TABLE LT_RETURN INTO LS_RETURN WITH KEY TYPE = 'E'.
        IF SY-SUBRC NE 0.
          READ TABLE LT_RETURN INTO LS_RETURN WITH KEY TYPE = 'A'.
        ENDIF.

        IF SY-SUBRC EQ 0.
          " Jika ada error/abort, JANGAN COMMIT! Lakukan Rollback
          CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
          LS_RESULT-STATUS  = 'E'.
          LS_RESULT-MESSAGE = LS_RETURN-MESSAGE.
          EXIT.
        ENDIF.
        " --- END FIX ---

        LS_RESULT-REL_CODE = LS_RELCODE-FRGCO.
        CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
          EXPORTING
            WAIT = 'X'.
        LS_RESULT-STATUS  = 'S'.
        LS_RESULT-MESSAGE = 'PO berhasil di-release otomatis (Sprint 1)'.
        LV_RELEASED = 'X'.
        EXIT.

      ELSE.
        CLEAR LS_RETURN.
        READ TABLE LT_RETURN INTO LS_RETURN INDEX 1.
        CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.

        IF LV_RETCODE EQ 4 OR LV_RETCODE EQ 6.
          CONTINUE.
        ELSE.
          LS_RESULT-STATUS = 'E'.
          IF LS_RETURN-MESSAGE IS NOT INITIAL.
            LS_RESULT-MESSAGE = LS_RETURN-MESSAGE.
          ELSE.
            LS_RESULT-MESSAGE = 'BAPI_PO_RELEASE gagal, cek exception'.
          ENDIF.
          EXIT.
        ENDIF.
      ENDIF.

    ENDLOOP.

    IF LV_RELEASED IS INITIAL AND LS_RESULT-STATUS IS INITIAL.
      LS_RESULT-STATUS  = 'W'.
      LS_RESULT-MESSAGE = 'Tidak ada release code yang applicable saat ini'.
    ENDIF.

    APPEND LS_RESULT TO LT_RESULT.

  ENDLOOP.

*----------------------------------------------------------------*
* 4. Output hasil
*----------------------------------------------------------------*
  DESCRIBE TABLE LT_RESULT LINES LV_LINES.

  WRITE: / 'Hasil PO Auto-Release Sprint 1 (v10)', 50 'Mode:', P_TEST AS CHECKBOX.
  WRITE: / 'Threshold auto-release: USD', LV_THRESHOLD_USD.
  WRITE: / 'Total PO diproses:', LV_LINES.
  SKIP.
  WRITE: / SY-ULINE.
  WRITE: / 'PO Number', 15 'USD Val', 35 'Rel.Code', 45 'Status', 55 'Keterangan'.
  WRITE: / SY-ULINE.

  LOOP AT LT_RESULT INTO LS_RESULT.
    WRITE: / LS_RESULT-EBELN,
             15 LS_RESULT-USDVAL,
             35 LS_RESULT-REL_CODE,
             45 LS_RESULT-STATUS,
             55 LS_RESULT-MESSAGE.
  ENDLOOP.

*----------------------------------------------------------------*
* SPRINT 2 (belum dibangun di sini -- sengaja dipisah):
* - Identifikasi approver (Lisa/Melisa/Fenny/GM Purchasing) utk PO
*   >= threshold, berdasarkan mapping ZMAP_TYPE TYPE='APPROVER'.
* - Email notifikasi ke approver (SO_NEW_DOCUMENT_ATT_SEND_API1).
* - Exception flagging (vendor/material baru, harga naik >10%,
*   no price history/stale >24 bulan, service/capex PO).
*----------------------------------------------------------------*