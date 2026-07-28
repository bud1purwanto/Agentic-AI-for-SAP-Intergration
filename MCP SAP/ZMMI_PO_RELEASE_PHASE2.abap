*&---------------------------------------------------------------*
*& Report  ZMMI_PO_RELEASE_PHASE2  (Sprint 2 - Routing + Exception)
*&---------------------------------------------------------------*

REPORT ZMMI_PO_RELEASE_PHASE2 LINE-SIZE 210.

TABLES: EKKO, EKPO.

*----------------------------------------------------------------*
* Konstanta konfigurasi exception
*----------------------------------------------------------------*
CONSTANTS: GC_MAP_PROG   TYPE ZMAP_TYPE-PROG VALUE 'ZMMI_PO_RELEASE',
           GC_NEW_DAYS   TYPE I              VALUE 90,     " master baru
           GC_STALE_DAYS TYPE I              VALUE 730,    " 24 bulan
           GC_PRICE_TOL  TYPE P DECIMALS 2   VALUE '1.10', " naik >10%
           GC_PSTYP_SVC  TYPE EKPO-PSTYP     VALUE '9',    " service
           GC_KNTTP_CPX  TYPE EKPO-KNTTP     VALUE 'A'.    " asset/capex

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
         LIFNR TYPE EKKO-LIFNR,
         LOEKZ TYPE EKKO-LOEKZ,
       END OF TY_EKKO.

TYPES: BEGIN OF TY_THRESHOLD,
         OPT    TYPE ZMAP_TYPE-OPT,
         VALUE  TYPE ZMAP_TYPE-VALUE,
         TEXT1  TYPE ZMAP_TYPE-TEXT1,
         USDVAL TYPE P DECIMALS 2,
       END OF TY_THRESHOLD.

TYPES: BEGIN OF TY_APPROVER,
         OPT   TYPE ZMAP_TYPE-OPT,
         VALUE TYPE ZMAP_TYPE-VALUE,
         TEXT1 TYPE ZMAP_TYPE-TEXT1,
       END OF TY_APPROVER.

TYPES: BEGIN OF TY_RELCODE,
         FRGCO TYPE T16FV-FRGCO,
       END OF TY_RELCODE.

TYPES: BEGIN OF TY_EKPOD,
         EBELP TYPE EKPO-EBELP,
         MATNR TYPE EKPO-MATNR,
         NETPR TYPE EKPO-NETPR,
         PEINH TYPE EKPO-PEINH,
         BPRME TYPE EKPO-BPRME,
         PSTYP TYPE EKPO-PSTYP,
         KNTTP TYPE EKPO-KNTTP,
       END OF TY_EKPOD.

TYPES: BEGIN OF TY_LAST,
         NETPR TYPE EKPO-NETPR,
         PEINH TYPE EKPO-PEINH,
         BPRME TYPE EKPO-BPRME,
         WAERS TYPE EKKO-WAERS,
         AEDAT TYPE EKKO-AEDAT,
       END OF TY_LAST.

TYPES: BEGIN OF TY_RESULT,
         EBELN     TYPE EKKO-EBELN,
         USDVAL    TYPE P DECIMALS 2,
         TIER      TYPE ZMAP_TYPE-OPT,
         REL_CODE  TYPE BAPIMMPARA-PO_REL_COD,
         APPR_NAME TYPE ZMAP_TYPE-VALUE,
         APPR_MAIL TYPE ZMAP_TYPE-TEXT1,
         STATUS    TYPE CHAR1,
         EXC_FLAG  TYPE CHAR1,
         EXC_REASON TYPE C LENGTH 120,
         MESSAGE   TYPE BAPI_MSG,
       END OF TY_RESULT.

DATA: LT_EKKO      TYPE STANDARD TABLE OF TY_EKKO,
      LS_EKKO      TYPE TY_EKKO,
      LT_THRESHOLD TYPE STANDARD TABLE OF TY_THRESHOLD,
      LS_THRESHOLD TYPE TY_THRESHOLD,
      LT_APPROVER  TYPE STANDARD TABLE OF TY_APPROVER,
      LS_APPROVER  TYPE TY_APPROVER,
      LT_RELCODE   TYPE STANDARD TABLE OF TY_RELCODE,
      LS_RELCODE   TYPE TY_RELCODE,
      LT_EKPOD     TYPE STANDARD TABLE OF TY_EKPOD,
      LS_EKPOD     TYPE TY_EKPOD,
      LT_RESULT    TYPE STANDARD TABLE OF TY_RESULT,
      LS_RESULT    TYPE TY_RESULT.

DATA: LV_NETWR     TYPE EKPO-NETWR,
      LV_REAL_NETWR TYPE BAPICURR-BAPICURR,
      LV_USDVAL    TYPE P DECIMALS 2,
      LV_KURS      TYPE RKB1K-EXCHR,
      LV_RELSTATUS TYPE BAPIMMPARA-REL_STATUS,
      LV_RELIND    TYPE BAPIMMPARA-PO_REL_IND,
      LV_RETCODE   TYPE SY-SUBRC,
      LV_RELEASED  TYPE CHAR1,
      LV_LINES     TYPE I,
      LV_FOUND     TYPE CHAR1,
      LV_AUTO      TYPE CHAR1.

DATA: LT_RETURN TYPE STANDARD TABLE OF BAPIRETURN,
      LS_RETURN TYPE BAPIRETURN.

* Kerja exception
DATA: LV_EXC        TYPE CHAR1,
      LV_CUTNEW     TYPE SY-DATUM,
      LV_CUTSTALE   TYPE SY-DATUM,
      LV_ERDAT      TYPE LFA1-ERDAT,
      LV_ERSDA      TYPE MARA-ERSDA,
      LV_DUMMY      TYPE EKKO-EBELN,
      LV_CURUNIT    TYPE P DECIMALS 4,
      LV_CURUSD     TYPE P DECIMALS 4,
      LS_LASTM      TYPE TY_LAST,
      LS_LASTV      TYPE TY_LAST,
      LV_LASTUSD    TYPE P DECIMALS 4,
      LV_HASMAT     TYPE CHAR1,
      LV_HASVEN     TYPE CHAR1.

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

  LV_CUTNEW   = SY-DATUM - GC_NEW_DAYS.
  LV_CUTSTALE = SY-DATUM - GC_STALE_DAYS.

*----------------------------------------------------------------*
* 1. Load mapping THRESHOLD (semua tier) dari ZMAP_TYPE
*----------------------------------------------------------------*
  REFRESH LT_THRESHOLD.
  SELECT OPT VALUE TEXT1
    INTO CORRESPONDING FIELDS OF TABLE LT_THRESHOLD
    FROM ZMAP_TYPE
    WHERE PROG = GC_MAP_PROG
      AND TYPE = 'THRESHOLD'
      AND DELETION = SPACE.

  IF LT_THRESHOLD IS INITIAL.
    WRITE: / 'Mapping THRESHOLD belum ada di ZMAP_TYPE. Program dihentikan.'.
    EXIT.
  ENDIF.

  LOOP AT LT_THRESHOLD INTO LS_THRESHOLD.
    LS_THRESHOLD-USDVAL = LS_THRESHOLD-VALUE.
    MODIFY LT_THRESHOLD FROM LS_THRESHOLD.
  ENDLOOP.

  SORT LT_THRESHOLD BY USDVAL ASCENDING.

*----------------------------------------------------------------*
* 2. Load mapping APPROVER (HANYA baris ber-email) dari ZMAP_TYPE
*----------------------------------------------------------------*
  REFRESH LT_APPROVER.
  SELECT OPT VALUE TEXT1
    INTO CORRESPONDING FIELDS OF TABLE LT_APPROVER
    FROM ZMAP_TYPE
    WHERE PROG = GC_MAP_PROG
      AND TYPE = 'APPROVER'
      AND DELETION = SPACE
      AND TEXT1 LIKE '%@%'.

  IF LT_APPROVER IS INITIAL.
    WRITE: / 'Mapping APPROVER (ber-email) belum ada di ZMAP_TYPE. Program dihentikan.'.
    EXIT.
  ENDIF.

*----------------------------------------------------------------*
* 3. Ambil PO yang masih PENDING RELEASE (FRGRL = 'X')
*----------------------------------------------------------------*
  REFRESH LT_EKKO.
  SELECT EBELN BUKRS EKORG EKGRP BSART FRGRL FRGGR FRGSX WAERS BEDAT LIFNR LOEKZ
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
* 4. Proses tiap PO
*----------------------------------------------------------------*
  LOOP AT LT_EKKO INTO LS_EKKO.

    CLEAR: LS_RESULT, LV_NETWR, LV_USDVAL, LV_RELEASED, LV_AUTO.
    LS_RESULT-EBELN = LS_EKKO-EBELN.

*   --- 4a. Total nilai PO ---
    SELECT SUM( NETWR ) INTO LV_NETWR
      FROM EKPO
      WHERE EBELN = LS_EKKO-EBELN
        AND LOEKZ EQ SPACE.

*   --- 4b. Konversi ke USD pakai KURS PADA TANGGAL PO (BEDAT) ---
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

*   --- 4c. Tentukan TIER dari mapping THRESHOLD (ascending) ---
    CLEAR: LV_FOUND, LV_AUTO.
    LOOP AT LT_THRESHOLD INTO LS_THRESHOLD.
      IF LV_USDVAL <= LS_THRESHOLD-USDVAL.
        LV_FOUND = 'X'.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF LV_FOUND IS INITIAL.
      LS_RESULT-STATUS  = 'E'.
      LS_RESULT-MESSAGE = 'Nilai PO melebihi tier tertinggi di mapping THRESHOLD -- wajib manual'.
      APPEND LS_RESULT TO LT_RESULT.
      CONTINUE.
    ENDIF.

    LS_RESULT-TIER = LS_THRESHOLD-OPT.
    IF LS_THRESHOLD-TEXT1 EQ 'X'.
      LV_AUTO = 'X'.
    ENDIF.

*   ================================================================
*   4d. JALUR AUTO (Tier T0) -> release lewat BAPI (warisan Sprint 1)
*   ================================================================
    IF LV_AUTO EQ 'X'.

      REFRESH LT_RELCODE.
      SELECT FRGCO
        INTO TABLE LT_RELCODE
        FROM T16FV
        WHERE FRGGR = LS_EKKO-FRGGR
          AND FRGSX = LS_EKKO-FRGSX.

      IF LT_RELCODE IS INITIAL.
        LS_RESULT-STATUS  = 'W'.
        LS_RESULT-MESSAGE = 'Tier auto tapi kombinasi FRGGR/FRGSX tidak ditemukan di T16FV'.
        APPEND LS_RESULT TO LT_RESULT.
        CONTINUE.
      ENDIF.

      LOOP AT LT_RELCODE INTO LS_RELCODE.

        IF P_TEST EQ 'X'.
          LS_RESULT-REL_CODE = LS_RELCODE-FRGCO.
          LS_RESULT-STATUS   = 'S'.
          LS_RESULT-MESSAGE  = 'Simulasi OK (Test Mode) -- AUTO release, BAPI TIDAK dipanggil'.
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

        LV_RETCODE = SY-SUBRC.

        IF LV_RETCODE EQ 0.
          " Cek apakah ada error (E) atau abort (A) di tabel RETURN
          READ TABLE LT_RETURN INTO LS_RETURN WITH KEY TYPE = 'E'.
          IF SY-SUBRC NE 0.
            READ TABLE LT_RETURN INTO LS_RETURN WITH KEY TYPE = 'A'.
          ENDIF.

          IF SY-SUBRC EQ 0.
            CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
            LS_RESULT-STATUS  = 'E'.
            LS_RESULT-MESSAGE = LS_RETURN-MESSAGE.
            EXIT.
          ENDIF.

          LS_RESULT-REL_CODE = LS_RELCODE-FRGCO.
          CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
            EXPORTING
              WAIT = 'X'.
          LS_RESULT-STATUS  = 'S'.
          LS_RESULT-MESSAGE = 'PO berhasil di-release otomatis (Tier T0)'.
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

*   ================================================================
*   4e. JALUR ROUTING (Tier T1/T2) -> approver + EXCEPTION FLAGGING
*   ================================================================
    ELSE.

*     --- 4e-1. Identifikasi approver ---
      CLEAR LS_APPROVER.
      IF LS_RESULT-TIER EQ 'T2'.
        READ TABLE LT_APPROVER INTO LS_APPROVER WITH KEY OPT = 'GM_FIXED'.
      ELSE.
        READ TABLE LT_APPROVER INTO LS_APPROVER WITH KEY OPT = LS_EKKO-EKGRP.
        IF SY-SUBRC NE 0.
          READ TABLE LT_APPROVER INTO LS_APPROVER WITH KEY OPT = 'DEFAULT'.
        ENDIF.
      ENDIF.

      IF SY-SUBRC EQ 0.
        LS_RESULT-APPR_NAME = LS_APPROVER-VALUE.
        LS_RESULT-APPR_MAIL = LS_APPROVER-TEXT1.
        LS_RESULT-STATUS    = 'M'.
        LS_RESULT-MESSAGE   = 'Perlu approval manual di SAP (email notif belum diaktifkan)'.
      ELSE.
        LS_RESULT-STATUS = 'E'.
        IF LS_RESULT-TIER EQ 'T2'.
          LS_RESULT-MESSAGE = 'Tidak ada mapping GM Purchasing (OPT=GM_FIXED) di ZMAP_TYPE'.
        ELSE.
          LS_RESULT-MESSAGE = 'Tidak ada mapping APPROVER utk EKGRP ini, baris DEFAULT juga tidak ada'.
        ENDIF.
      ENDIF.

*     --- 4e-2. EXCEPTION FLAGGING (hanya T1/T2) ---
      CLEAR: LV_EXC, LS_RESULT-EXC_FLAG, LS_RESULT-EXC_REASON.

*     Kriteria VendorBaru: master data baru ATAU belum pernah beli.
      CLEAR LV_ERDAT.
      SELECT SINGLE ERDAT INTO LV_ERDAT FROM LFA1
        WHERE LIFNR = LS_EKKO-LIFNR.
      IF SY-SUBRC EQ 0 AND LV_ERDAT GE LV_CUTNEW.
        LV_EXC = 'X'.
        PERFORM F_ADD_REASON USING 'VendorBaru'
                             CHANGING LS_RESULT-EXC_REASON.
      ELSE.
        CLEAR LV_DUMMY.
        SELECT EBELN INTO LV_DUMMY UP TO 1 ROWS
          FROM EKKO
          WHERE LIFNR = LS_EKKO-LIFNR
            AND EBELN NE LS_EKKO-EBELN
            AND FRGZU = 'X'
            AND BSTYP = 'F'.
        ENDSELECT.
        IF SY-SUBRC NE 0.
          LV_EXC = 'X'.
          PERFORM F_ADD_REASON USING 'VendorBaru'
                               CHANGING LS_RESULT-EXC_REASON.
        ENDIF.
      ENDIF.

*     Ambil detail item PO ini utk cek per material.
      REFRESH LT_EKPOD.
      SELECT EBELP MATNR NETPR PEINH BPRME PSTYP KNTTP
        INTO TABLE LT_EKPOD
        FROM EKPO
        WHERE EBELN = LS_EKKO-EBELN
          AND LOEKZ EQ SPACE.

      LOOP AT LT_EKPOD INTO LS_EKPOD.

*       Kriteria SvcCapex: service (PSTYP) atau capex (KNTTP).
        IF LS_EKPOD-PSTYP EQ GC_PSTYP_SVC OR LS_EKPOD-KNTTP EQ GC_KNTTP_CPX.
          LV_EXC = 'X'.
          PERFORM F_ADD_REASON USING 'SvcCapex'
                               CHANGING LS_RESULT-EXC_REASON.
        ENDIF.

*       Cek material hanya bila ada nomor material.
        IF LS_EKPOD-MATNR IS INITIAL.
          CONTINUE.
        ENDIF.

*       Kriteria MaterialBaru (master baru): MARA-ERSDA.
        CLEAR LV_ERSDA.
        SELECT SINGLE ERSDA INTO LV_ERSDA FROM MARA
          WHERE MATNR = LS_EKPOD-MATNR.
        IF SY-SUBRC EQ 0 AND LV_ERSDA GE LV_CUTNEW.
          LV_EXC = 'X'.
          PERFORM F_ADD_REASON USING 'MaterialBaru'
                               CHANGING LS_RESULT-EXC_REASON.
        ENDIF.

*       Harga unit PO sekarang -> USD.
        CLEAR: LV_CURUNIT, LV_CURUSD.
        IF LS_EKPOD-PEINH > 0.
          LV_CURUNIT = LS_EKPOD-NETPR / LS_EKPOD-PEINH.
        ELSE.
          LV_CURUNIT = LS_EKPOD-NETPR.
        ENDIF.
        PERFORM F_TO_USD USING LV_CURUNIT LS_EKKO-WAERS LS_EKKO-BEDAT
                         CHANGING LV_CURUSD.

*       Harga terakhir MATERIAL (vendor manapun).
        CLEAR: LS_LASTM, LV_HASMAT.
        PERFORM F_GET_LAST USING LS_EKPOD-MATNR SPACE LS_EKKO-EBELN
                           CHANGING LS_LASTM LV_HASMAT.

*       Harga terakhir VENDOR (material sama + vendor sama).
        CLEAR: LS_LASTV, LV_HASVEN.
        PERFORM F_GET_LAST USING LS_EKPOD-MATNR LS_EKKO-LIFNR LS_EKKO-EBELN
                           CHANGING LS_LASTV LV_HASVEN.

*       MaterialBaru (never purchased): tidak ada histori material.
        IF LV_HASMAT IS INITIAL.
          LV_EXC = 'X'.
          PERFORM F_ADD_REASON USING 'MaterialBaru'
                               CHANGING LS_RESULT-EXC_REASON.
        ELSE.
*         Ada histori material -> cek stale & naik harga (sumbu material).
          IF LS_LASTM-AEDAT LT LV_CUTSTALE.
            LV_EXC = 'X'.
            PERFORM F_ADD_REASON USING 'StaleHist'
                                 CHANGING LS_RESULT-EXC_REASON.
          ELSE.
            PERFORM F_CHK_NAIK USING LV_CURUSD LS_EKPOD-BPRME LS_LASTM
                               'HrgNaikMat'
                               CHANGING LV_EXC LS_RESULT-EXC_REASON.
          ENDIF.
        ENDIF.

*       Naik harga sumbu VENDOR (hanya bila ada histori vendor & fresh).
        IF LV_HASVEN IS NOT INITIAL AND LS_LASTV-AEDAT GE LV_CUTSTALE.
          PERFORM F_CHK_NAIK USING LV_CURUSD LS_EKPOD-BPRME LS_LASTV
                             'HrgNaikVen'
                             CHANGING LV_EXC LS_RESULT-EXC_REASON.
        ENDIF.

      ENDLOOP.

      LS_RESULT-EXC_FLAG = LV_EXC.

    ENDIF.

    APPEND LS_RESULT TO LT_RESULT.

  ENDLOOP.

*----------------------------------------------------------------*
* 5. Output hasil
*----------------------------------------------------------------*
  DESCRIBE TABLE LT_RESULT LINES LV_LINES.

  WRITE: / 'Hasil PO Routing + Exception (PHASE2)', 60 'Mode:', P_TEST AS CHECKBOX.
  WRITE: / 'Total PO diproses:', LV_LINES.
  SKIP.
  WRITE: / SY-ULINE.
  WRITE: / 'PO Number', 15 'USD Val', 35 'Tier', 42 'RelCd',
           50 'Approver', 67 'Email', 90 'St', 94 'Ex',
           98 'Alasan Exception', 160 'Keterangan'.
  WRITE: / SY-ULINE.

  LOOP AT LT_RESULT INTO LS_RESULT.
    WRITE: / LS_RESULT-EBELN,
             15 LS_RESULT-USDVAL,
             35 LS_RESULT-TIER,
             42 LS_RESULT-REL_CODE,
             50 LS_RESULT-APPR_NAME,
             67 LS_RESULT-APPR_MAIL,
             90 LS_RESULT-STATUS,
             94 LS_RESULT-EXC_FLAG,
             98(60) LS_RESULT-EXC_REASON,
             160 LS_RESULT-MESSAGE.
  ENDLOOP.

*&---------------------------------------------------------------*
*& Form F_ADD_REASON  -- tambah token reason bila belum ada
*&---------------------------------------------------------------*
FORM F_ADD_REASON USING P_TOKEN TYPE C
                  CHANGING P_REASON TYPE C.
  IF P_REASON CS P_TOKEN.
    RETURN.
  ENDIF.
  IF P_REASON IS INITIAL.
    P_REASON = P_TOKEN.
  ELSE.
    CONCATENATE P_REASON P_TOKEN INTO P_REASON SEPARATED BY ';'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------*
*& Form F_TO_USD  -- konversi amount ke USD di tanggal tertentu
*&---------------------------------------------------------------*
FORM F_TO_USD USING P_AMT TYPE P P_WAERS TYPE WAERS P_DATE TYPE SY-DATUM
              CHANGING P_USD TYPE P.
  DATA: LV_R TYPE RKB1K-EXCHR,
        LV_REAL_AMT TYPE BAPICURR-BAPICURR.
  IF P_WAERS EQ 'USD'.
    P_USD = P_AMT.
    RETURN.
  ENDIF.

  CALL FUNCTION 'BAPI_CURRENCY_CONV_TO_EXTERNAL'
    EXPORTING
      CURRENCY        = P_WAERS
      AMOUNT_INTERNAL = P_AMT
    IMPORTING
      AMOUNT_EXTERNAL = LV_REAL_AMT.

  CLEAR LV_R.
  CALL FUNCTION 'RKC_SINGLE_EXCHANGE_RATE_GET'
    EXPORTING
      DATUM         = P_DATE
      KURST         = 'M'
      NCURR         = 'USD'
      VCURR         = P_WAERS
    IMPORTING
      EXCHR         = LV_R
    EXCEPTIONS
      NO_RATE_FOUND = 1
      OTHERS        = 2.
  IF SY-SUBRC EQ 0.
    P_USD = LV_REAL_AMT * LV_R.
  ELSE.
    P_USD = 0.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------*
*& Form F_GET_LAST  -- harga PO released terakhir utk material
*&                     (opsional filter vendor). EBELN < current.
*&---------------------------------------------------------------*
FORM F_GET_LAST USING P_MATNR TYPE MATNR P_LIFNR TYPE LIFNR
                      P_EBELN TYPE EBELN
                CHANGING P_LAST TYPE TY_LAST P_HAS TYPE C.
  CLEAR: P_LAST, P_HAS.
  IF P_LIFNR IS INITIAL.
    SELECT B~NETPR B~PEINH B~BPRME A~WAERS A~AEDAT
      INTO P_LAST UP TO 1 ROWS
      FROM EKKO AS A INNER JOIN EKPO AS B ON B~EBELN = A~EBELN
      WHERE B~MATNR = P_MATNR
        AND B~LOEKZ = SPACE
        AND A~EBELN < P_EBELN
        AND A~FRGZU = 'X'
        AND A~BSTYP = 'F'
      ORDER BY A~EBELN DESCENDING.
    ENDSELECT.
  ELSE.
    SELECT B~NETPR B~PEINH B~BPRME A~WAERS A~AEDAT
      INTO P_LAST UP TO 1 ROWS
      FROM EKKO AS A INNER JOIN EKPO AS B ON B~EBELN = A~EBELN
      WHERE B~MATNR = P_MATNR
        AND A~LIFNR = P_LIFNR
        AND B~LOEKZ = SPACE
        AND A~EBELN < P_EBELN
        AND A~FRGZU = 'X'
        AND A~BSTYP = 'F'
      ORDER BY A~EBELN DESCENDING.
    ENDSELECT.
  ENDIF.
  IF SY-SUBRC EQ 0.
    P_HAS = 'X'.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------*
*& Form F_CHK_NAIK  -- bandingkan harga USD skrg vs harga terakhir
*&                     (normalisasi PEINH + USD), unit BPRME sama.
*&---------------------------------------------------------------*
FORM F_CHK_NAIK USING P_CURUSD TYPE P P_BPRME TYPE BPRME
                      P_LAST TYPE TY_LAST P_TOKEN TYPE C
                CHANGING P_EXC TYPE C P_REASON TYPE C.
  DATA: LV_UNIT TYPE P DECIMALS 4,
        LV_USD  TYPE P DECIMALS 4.
  IF P_LAST-BPRME NE P_BPRME.
    RETURN.
  ENDIF.
  IF P_LAST-PEINH > 0.
    LV_UNIT = P_LAST-NETPR / P_LAST-PEINH.
  ELSE.
    LV_UNIT = P_LAST-NETPR.
  ENDIF.
  PERFORM F_TO_USD USING LV_UNIT P_LAST-WAERS P_LAST-AEDAT
                   CHANGING LV_USD.
  IF LV_USD > 0 AND P_CURUSD > LV_USD * GC_PRICE_TOL.
    P_EXC = 'X'.
    PERFORM F_ADD_REASON USING P_TOKEN CHANGING P_REASON.
  ENDIF.
ENDFORM.