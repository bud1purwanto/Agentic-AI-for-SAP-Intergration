*&---------------------------------------------------------------------*
*&  Report     :  ZPPI_COHVPI                                          *
*&  Appl. Area :  PP                                                   *
*&  Created by :  J. Budi                                              *
*&  Created on :  6 August 2025                                        *
*&  Modified   :  08.07.2026 - Fix #1 (deteksi error TECO) & #2 (rollback) *
*&---------------------------------------------------------------------*

REPORT  ZPPI_COHVPI.

TYPES: BEGIN OF T_TAB,
       AUFNR          TYPE AUFNR,
       AUART          TYPE AUART,
       GRUP           TYPE C LENGTH 15,     "Grup order type dari ZMAP_TYPE
       START          TYPE PM_ORDGSTRP,
       END            TYPE CO_GLTRP,
       AUTYP          TYPE AUFTYP,
       ERDAT          TYPE ERDAT,
       STATUS         TYPE CHAR100,
       MATNR          TYPE MATNR,           "Material No
       TARGET         TYPE GAMNG,
       TARGET2        TYPE CHAR50,
       MEINS          TYPE MEINS,
       MAKTX          TYPE MAKTX,
       WERKS          TYPE WERKS_D,         "Plant
       LGORT          TYPE LGORT_D,         "Storage Location
       CHARG          TYPE CHARG_D,         "Batch
       MBLNR          TYPE MBLNR,           "Matdoc SR Number
       SMBLN          TYPE MBLNR,           "Matdoc SR Number Cancel
       MJAHR          TYPE MJAHR,           "Matdoc SR Year
       SJAHR          TYPE MJAHR,           "Matdoc SR Year Cancel
       ZEILE          TYPE MBLPO,           "Matdoc SR Item
       SMBLP          TYPE MBLPO,           "Matdoc SR Item Cancel
       BWART          TYPE BWART,           "Movement Type
       COMB_ORD       TYPE AUFNR,
       "Custom ALV
       LINE_COLOR     TYPE C LENGTH 4,      "Color
       BOX,                                 "Choice
       ERR,                                 "Error Mark
       INDC           TYPE C LENGTH 4,      "Indicator
       MESS           TYPE C LENGTH 220,    "Message (BAPI_MSG = 220)
       END OF T_TAB.

"--- Types untuk optimasi (prefetch/cache) ---
TYPES: BEGIN OF TY_STAT, AUFNR TYPE AUFNR, STTXT TYPE BSVX-STTXT, END OF TY_STAT.
TYPES: BEGIN OF TY_OBJ,  AUFNR TYPE AUFNR, OBJNR TYPE J_OBJNR,    END OF TY_OBJ.
TYPES: BEGIN OF TY_MILL, AUFNR TYPE AUFNR, PARENT TYPE AUFNR,     END OF TY_MILL.
TYPES: BEGIN OF TY_AFKO, AUFNR TYPE AUFNR, GAMNG TYPE GAMNG, GMEIN TYPE AFKO-GMEIN,
                         GSTRP TYPE AFKO-GSTRP, GLTRP TYPE AFKO-GLTRP, END OF TY_AFKO.
TYPES: BEGIN OF TY_MAKT, MATNR TYPE MATNR, MAKTX TYPE MAKTX, END OF TY_MAKT.
TYPES: BEGIN OF TY_MATN, MATNR TYPE MATNR, END OF TY_MATN.

"--- Mapping order type -> grup (sumber: tabel ZMAP_TYPE) ---
TYPES: BEGIN OF TY_MAP,  AUART TYPE AUART, GRUP TYPE C LENGTH 15, END OF TY_MAP.
TYPES: BEGIN OF TY_MAPR, OPT TYPE ZMAP_TYPE-OPT, VALUE TYPE ZMAP_TYPE-VALUE,
                         END OF TY_MAPR.


"For Display
DATA: IT_MOVEMENT TYPE STANDARD TABLE OF T_TAB WITH HEADER LINE.

DATA: IT_CHECK_CANC LIKE IT_MOVEMENT OCCURS 0 WITH HEADER LINE.
DATA: IT_AUFNR      LIKE IT_MOVEMENT OCCURS 0 WITH HEADER LINE.
DATA: ITAB          LIKE IT_MOVEMENT OCCURS 0 WITH HEADER LINE.

"Other Internal Table
DATA: WA_CELL_COLOR   TYPE LVC_S_SCOL,
      CELL_COLOUR     LIKE WA_CELL_COLOR-COLOR-COL,
      L_REF_GRID      TYPE REF TO CL_GUI_ALV_GRID.

CONSTANTS:
      ERROR(4)        TYPE C VALUE '@0A@',       "Error
      SUCCES(4)       TYPE C VALUE '@08@',       "Success
      WARNING(4)      TYPE C VALUE '@09@',       "Warning
      GREY(4)         TYPE C VALUE '@EB@'.       "Grey

"--- Progress indicator: tahap proses (dipakai FORM SET_INDICATOR) ---
CONSTANTS:
      C_STEP_GET(1)     TYPE C VALUE '1',        "Cek data movement
      C_STEP_CANCEL(1)  TYPE C VALUE '2',        "Bersihkan data cancel
      C_STEP_STATUS(1)  TYPE C VALUE '3',        "Baca status order
      C_STEP_BUILD(1)   TYPE C VALUE '4',        "Susun data order
      C_STEP_TECO(1)    TYPE C VALUE '5',        "Proses TECO
      C_STEP_REFRESH(1) TYPE C VALUE '6',        "Refresh data & status
      C_TOTAL_STEP      TYPE I VALUE 6.          "Total tahap

DATA: V_TFILL LIKE SY-TFILL.

DATA: BACK TYPE C.                               "Flag stop (belum ada UI, selalu SPACE)

"ALV
DATA: OK_CODE         LIKE SY-UCOMM,
      SAVE_OK         LIKE SY-UCOMM,
      DIALOG_BOX      TYPE REF TO CL_GUI_DIALOGBOX_CONTAINER,
      GRID1           TYPE REF TO CL_GUI_ALV_GRID,
      GS_LAYOUT       TYPE LVC_S_LAYO,
      G_MAX           TYPE I VALUE 10,
      GT_FIELDCAT     TYPE LVC_T_FCAT,
      GS_VARIANT      TYPE DISVARIANT,
      LT_ROW_NO       TYPE LVC_T_ROID WITH HEADER LINE.

DATA: TY_EMAIL TYPE AD_SMTPADR,
      V_OBJNR           LIKE AUFK-OBJNR,
      V_ORD_STAT        LIKE BSVX-STTXT.

"Create Order
DATA: TORDER            LIKE BAPI_PI_ORDER_CREATE,
      ORDERO            LIKE BAPI_ORDER_KEY-ORDER_NUMBER,
      TECOORDER         LIKE BAPI_ORDER_KEY OCCURS 0 WITH HEADER LINE,
      IT_TECO           LIKE JSTAT OCCURS 0 WITH HEADER LINE.

CLASS CL_BCS DEFINITION LOAD.
DATA: LO_SEND_REQUEST TYPE REF TO CL_BCS VALUE IS INITIAL,
      LO_DOCUMENT TYPE REF TO CL_DOCUMENT_BCS VALUE IS INITIAL, "document object
      I_TEXT TYPE BCSY_TEXT, "Table for body
      W_TEXT LIKE LINE OF I_TEXT, "work area for message body
      LO_SENDER TYPE REF TO IF_SENDER_BCS VALUE IS INITIAL, "sender
      LO_RECIPIENT TYPE REF TO IF_RECIPIENT_BCS VALUE IS INITIAL. "recipient

DATA: LV_STRING TYPE STRING,
      LV_STRING2 TYPE STRING,
      LV_DATA_STRING TYPE STRING,
      LV_XSTRING TYPE XSTRING,
      LIT_BINARY_CONTENT TYPE SOLIX_TAB,
      L_ATTSUBJECT TYPE SOOD-OBJDES.

"For Return
DATA: IT_RETURN         LIKE STANDARD TABLE OF BAPIRET2 WITH HEADER LINE.

"Cache/prefetch tables (optimasi performa)
DATA: GT_STAT TYPE STANDARD TABLE OF TY_STAT WITH HEADER LINE,
      GT_MILL TYPE STANDARD TABLE OF TY_MILL WITH HEADER LINE.

INCLUDE ZABAPALV.

TABLES: AUFK, MKPF, MSEG.

"Cache mapping order type -> grup, dan range order type hasil mapping
DATA:   GT_MAP TYPE STANDARD TABLE OF TY_MAP WITH HEADER LINE.
RANGES: R_AUART FOR AUFK-AUART.


"--- Pilihan mode: Transaksi TECO / Report TECO ---
SELECTION-SCREEN BEGIN OF BLOCK BLK0 WITH FRAME TITLE TEXT-000.
PARAMETERS: RB1 RADIOBUTTON GROUP RB DEFAULT 'X' USER-COMMAND UCMD.  "Transaksi TECO
PARAMETERS: RB2 RADIOBUTTON GROUP RB.                                "Report TECO
SELECTION-SCREEN END OF BLOCK BLK0.

SELECTION-SCREEN BEGIN OF BLOCK BLK1 WITH FRAME TITLE TEXT-001.
SELECT-OPTIONS: S_BUDAT FOR MKPF-BUDAT.
SELECT-OPTIONS: S_AUFNR FOR AUFK-AUFNR    NO INTERVALS.   "Nomor PRO (opsional, pakai index PK)
SELECT-OPTIONS: S_AUTYP FOR AUFK-AUTYP    NO INTERVALS.
SELECT-OPTIONS: S_BWART FOR MSEG-BWART    NO INTERVALS.
SELECTION-SCREEN END OF BLOCK BLK1.

"--- Opsi khusus mode Transaksi (Radio 1) ---
SELECTION-SCREEN BEGIN OF BLOCK BLK3 WITH FRAME TITLE TEXT-003.
PARAMETERS: P_TEST AS CHECKBOX MODIF ID M1.   "Test Run (tidak commit, rollback)
SELECTION-SCREEN END OF BLOCK BLK3.

"--- Opsi khusus mode Report (Radio 2) - filter status order ---
SELECTION-SCREEN BEGIN OF BLOCK BLK4 WITH FRAME TITLE TEXT-004.
PARAMETERS: P_REL  AS CHECKBOX MODIF ID M2 DEFAULT 'X'.   "Released
PARAMETERS: P_TECO AS CHECKBOX MODIF ID M2.               "TECO
SELECTION-SCREEN END OF BLOCK BLK4.

"--- Email (hanya relevan untuk mode Transaksi) ---
SELECTION-SCREEN BEGIN OF BLOCK BLK2 WITH FRAME TITLE TEXT-002.
SELECT-OPTIONS: PA_TO  FOR TY_EMAIL NO INTERVALS MODIF ID M1.
SELECT-OPTIONS: PA_CC  FOR TY_EMAIL NO INTERVALS MODIF ID M1.
SELECT-OPTIONS: PA_BCC FOR TY_EMAIL NO INTERVALS MODIF ID M1.
SELECTION-SCREEN END OF BLOCK BLK2.

INITIALIZATION.
  PERFORM SET_BWART_DEFAULT.   "default movement type sesuai spec, bisa diubah user

AT SELECTION-SCREEN OUTPUT.
  PERFORM SET_SCREEN_MODE.     "tampil/sembunyi checkbox sesuai radio button

START-OF-SELECTION.
  PERFORM VALIDATION.
  PERFORM LOAD_ORDER_TYPE_MAP.    "order type diambil dari ZMAP_TYPE

  IF RB1 = 'X'.
    "=== Mode Transaksi TECO ===
    PERFORM GET_DATA.
    PERFORM TECO.
    PERFORM REFRESH USING 'X'.        "status fresh setelah TECO
    IF P_TEST IS INITIAL.
      PERFORM SEND_EMAIL.             "test run: tidak kirim email
    ENDIF.
    PERFORM DISPLAY_ALV.              "tampilkan hasil setelah transaksi
  ELSE.
    "=== Mode Report TECO (read-only, tanpa TECO & tanpa email) ===
    PERFORM GET_DATA.
    PERFORM FILTER_REPORT_STATUS.     "saring sesuai status yang dicentang
    IF ITAB[] IS INITIAL.
      MESSAGE 'Data tidak ditemukan untuk status yang dipilih!' TYPE 'S' DISPLAY LIKE 'E'.
      LEAVE LIST-PROCESSING.
    ENDIF.
    PERFORM DISPLAY_ALV.
  ENDIF.

END-OF-SELECTION.

*&---------------------------------------------------------------------*
*&      Form  VALIDATION
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM VALIDATION.
  IF S_BUDAT[] IS INITIAL.
    MESSAGE 'Please fill the parameters!' TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  "Mode transaksi (bukan test run) wajib isi email penerima
  IF RB1 = 'X' AND P_TEST IS INITIAL AND PA_TO[] IS INITIAL.
    MESSAGE 'Isi email penerima (To) untuk mode transaksi!' TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.

*  IF S_WERKS[] IS INITIAL.
*    MESSAGE 'Please fill plant!' TYPE 'S' DISPLAY LIKE 'E'.
*    LEAVE LIST-PROCESSING.
*  ENDIF.

ENDFORM.                    "VALIDATION

*&---------------------------------------------------------------------*
*&      Form  LOAD_ORDER_TYPE_MAP
*&---------------------------------------------------------------------*
*   Baca mapping order type dari tabel ZMAP_TYPE (pengganti parameter
*   S_AUART). Kunci: PROG = ZPPI_COHVPI, TYPE = ORDER TYPE.
*   OPT   = grup (JR / SR ORIGINAL / SR COMBINE / OTHERS)
*   VALUE = order type
*   Hasil: GT_MAP (cache order type -> grup) & R_AUART (range seleksi).
*----------------------------------------------------------------------*
FORM LOAD_ORDER_TYPE_MAP.
  DATA: LT_MAPR TYPE STANDARD TABLE OF TY_MAPR WITH HEADER LINE.

  REFRESH: GT_MAP, R_AUART.

  SELECT OPT VALUE INTO TABLE LT_MAPR
    FROM ZMAP_TYPE
    WHERE PROG     = 'ZPPI_COHVPI'
      AND TYPE     = 'ORDER TYPE'
      AND DELETION = SPACE.

  IF LT_MAPR[] IS INITIAL.
    MESSAGE 'Mapping order type di ZMAP_TYPE belum diisi!' TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  LOOP AT LT_MAPR.
    CLEAR GT_MAP.
    GT_MAP-AUART = LT_MAPR-VALUE.
    GT_MAP-GRUP  = LT_MAPR-OPT.
    APPEND GT_MAP.

    CLEAR R_AUART.
    R_AUART-SIGN   = 'I'.
    R_AUART-OPTION = 'EQ'.
    R_AUART-LOW    = LT_MAPR-VALUE.
    APPEND R_AUART.
  ENDLOOP.

  SORT GT_MAP BY AUART.
  DELETE ADJACENT DUPLICATES FROM GT_MAP COMPARING AUART.
ENDFORM.                    "LOAD_ORDER_TYPE_MAP

*&---------------------------------------------------------------------*
*&      Form  GET_GROUP
*&---------------------------------------------------------------------*
*   Ambil nama grup untuk sebuah order type dari cache GT_MAP.
*----------------------------------------------------------------------*
FORM GET_GROUP USING P_AUART CHANGING P_GRUP.
  CLEAR P_GRUP.
  READ TABLE GT_MAP WITH KEY AUART = P_AUART BINARY SEARCH.
  IF SY-SUBRC = 0.
    P_GRUP = GT_MAP-GRUP.
  ELSE.
    P_GRUP = 'UNMAPPED'.
  ENDIF.
ENDFORM.                    "GET_GROUP

*&---------------------------------------------------------------------*
*&      Form  SET_SCREEN_MODE
*&---------------------------------------------------------------------*
*   Tampilkan/sembunyikan field sesuai radio button:
*   - RB1 (Transaksi): tampil grup M1 (Test Run + Email), sembunyi M2
*   - RB2 (Report)   : tampil grup M2 (status Rel/TECO), sembunyi M1
*----------------------------------------------------------------------*
FORM SET_SCREEN_MODE.
  LOOP AT SCREEN.
    IF RB1 = 'X'.
      IF SCREEN-GROUP1 = 'M2'.
        SCREEN-ACTIVE = '0'.
        MODIFY SCREEN.
      ENDIF.
    ELSE.
      IF SCREEN-GROUP1 = 'M1'.
        SCREEN-ACTIVE = '0'.
        MODIFY SCREEN.
      ENDIF.
    ENDIF.
  ENDLOOP.
ENDFORM.                    "SET_SCREEN_MODE

*&---------------------------------------------------------------------*
*&      Form  FILTER_REPORT_STATUS
*&---------------------------------------------------------------------*
*   Mode Report: saring ITAB sesuai status yang dicentang.
*   Bila kedua checkbox kosong -> tampilkan semua (tidak menyaring).
*----------------------------------------------------------------------*
FORM FILTER_REPORT_STATUS.
  DATA: L_KEEP TYPE C.

  IF P_REL IS INITIAL AND P_TECO IS INITIAL.
    RETURN.
  ENDIF.

  LOOP AT ITAB.
    CLEAR L_KEEP.
    IF P_REL = 'X' AND ITAB-STATUS CP '*REL*'.
      L_KEEP = 'X'.
    ENDIF.
    IF P_TECO = 'X' AND ITAB-STATUS CP '*TECO*'.
      L_KEEP = 'X'.
    ENDIF.
    IF L_KEEP IS INITIAL.
      DELETE ITAB.
    ENDIF.
  ENDLOOP.
ENDFORM.                    "FILTER_REPORT_STATUS

*&---------------------------------------------------------------------*
*&      Form  GET_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM GET_DATA.
  "Get Preview
  SELECT
    MSEG~AUFNR
    AUFK~AUART
    AUFK~AUTYP
    AUFK~ERDAT
    MSEG~MATNR
    MSEG~WERKS
    MSEG~LGORT
    MSEG~CHARG
    MSEG~MBLNR
    MSEG~SMBLN
    MSEG~MJAHR
    MSEG~SJAHR
    MSEG~ZEILE
    MSEG~SMBLP
    MSEG~BWART
    INTO CORRESPONDING FIELDS OF TABLE IT_MOVEMENT
    FROM MKPF
    JOIN MSEG ON MSEG~MBLNR EQ MKPF~MBLNR AND MSEG~MJAHR EQ MKPF~MJAHR
    JOIN AUFK ON AUFK~AUFNR EQ MSEG~AUFNR
    JOIN AFPO ON AFPO~AUFNR EQ MSEG~AUFNR
   WHERE MKPF~BUDAT IN S_BUDAT
       AND AUFK~AUFNR IN S_AUFNR      "filter nomor PRO (opsional, index PK AUFK)
       AND AUFK~AUART IN R_AUART      "grup order type dari ZMAP_TYPE
       AND AUFK~AUTYP IN S_AUTYP
       AND MSEG~BWART IN S_BWART.     "filter movement type dari selection screen

  IT_CHECK_CANC[] = IT_MOVEMENT[].
  "Delete Cancel
  DELETE IT_CHECK_CANC WHERE SMBLN IS INITIAL.

  DESCRIBE TABLE IT_CHECK_CANC LINES V_TFILL.
  LOOP AT IT_CHECK_CANC.
    PERFORM SET_INDICATOR USING SY-TABIX V_TFILL C_STEP_CANCEL C_TOTAL_STEP
                                'Membersihkan data movement cancel...'.
    DELETE IT_MOVEMENT WHERE MBLNR EQ IT_CHECK_CANC-SMBLN AND MJAHR EQ IT_CHECK_CANC-SJAHR AND ZEILE EQ IT_CHECK_CANC-SMBLP.
  ENDLOOP.
*  DELETE IT_MOVEMENT WHERE SMBLN IS NOT INITIAL OR BWART EQ 102.

  IT_AUFNR[] = IT_MOVEMENT[].
  SORT IT_AUFNR BY AUFNR.
  DELETE ADJACENT DUPLICATES FROM IT_AUFNR COMPARING AUFNR.

  "Prefetch: status 1x/order (bukan 3-4x) & combine order 1x bulk (bukan full scan/order)
  PERFORM PREFETCH_STATUS.
  PERFORM PREFETCH_MILL.

  DESCRIBE TABLE IT_AUFNR LINES V_TFILL.
  LOOP AT IT_AUFNR.
    PERFORM SET_INDICATOR USING SY-TABIX V_TFILL C_STEP_BUILD C_TOTAL_STEP
                                'Menyusun data order...'.
    MOVE-CORRESPONDING IT_AUFNR TO ITAB.

    PERFORM GET_STATUS_CACHED USING IT_AUFNR-AUFNR CHANGING V_ORD_STAT.
*    IF V_ORD_STAT CP '*TECO*'.
*      DELETE ITAB.
*      CONTINUE.
*    ENDIF.

    "Ganti SELECT SINGLE AFPO per order (MILL_OC_AUFNR_U non-key -> full scan)
    READ TABLE GT_MILL WITH KEY PARENT = IT_AUFNR-AUFNR BINARY SEARCH.
    IF SY-SUBRC EQ 0.
      IT_AUFNR-COMB_ORD = GT_MILL-AUFNR.
      IT_AUFNR-STATUS = V_ORD_STAT.
      MODIFY IT_AUFNR.
      CLEAR IT_AUFNR.
    ELSE.
      ITAB-STATUS = V_ORD_STAT.
      APPEND ITAB.
      CLEAR ITAB.
    ENDIF.
  ENDLOOP.

  IF ITAB[] IS INITIAL.
    MESSAGE 'Data not found!' TYPE 'S' DISPLAY LIKE 'E'.
    LEAVE LIST-PROCESSING.
  ENDIF.

  PERFORM REFRESH USING SPACE.        "pakai status cache (belum TECO)
ENDFORM.                    "GET_PREVIEW

*&---------------------------------------------------------------------*
*&      Form  SET_BWART_DEFAULT
*&---------------------------------------------------------------------*
*   Default movement type sesuai spec Validasi TECO (editable di screen).
*----------------------------------------------------------------------*
FORM SET_BWART_DEFAULT.
  DATA: LT_B TYPE TABLE OF BWART,
        L_B  TYPE BWART.
  REFRESH S_BWART.
  APPEND '101' TO LT_B. APPEND '102' TO LT_B.
  APPEND '261' TO LT_B. APPEND '262' TO LT_B.
  APPEND '531' TO LT_B. APPEND '532' TO LT_B.
  APPEND '901' TO LT_B. APPEND '902' TO LT_B.
  LOOP AT LT_B INTO L_B.
    S_BWART-SIGN   = 'I'.
    S_BWART-OPTION = 'EQ'.
    S_BWART-LOW    = L_B.
    APPEND S_BWART.
  ENDLOOP.
ENDFORM.                    "SET_BWART_DEFAULT

*&---------------------------------------------------------------------*
*&      Form  PREFETCH_STATUS
*&---------------------------------------------------------------------*
*   Baca OBJNR massal, lalu status 1x per order ke cache GT_STAT.
*----------------------------------------------------------------------*
FORM PREFETCH_STATUS.
  DATA: LT_OBJ TYPE STANDARD TABLE OF TY_OBJ WITH HEADER LINE.
  REFRESH GT_STAT.
  IF IT_AUFNR[] IS INITIAL.
    RETURN.
  ENDIF.

  SELECT AUFNR OBJNR INTO TABLE LT_OBJ
    FROM AUFK
    FOR ALL ENTRIES IN IT_AUFNR
    WHERE AUFNR = IT_AUFNR-AUFNR.

  DESCRIBE TABLE LT_OBJ LINES V_TFILL.
  LOOP AT LT_OBJ.
    PERFORM SET_INDICATOR USING SY-TABIX V_TFILL C_STEP_STATUS C_TOTAL_STEP
                                'Membaca status order...'.
    CLEAR GT_STAT.
    GT_STAT-AUFNR = LT_OBJ-AUFNR.
    CALL FUNCTION 'AIP9_STATUS_READ'
      EXPORTING
        I_OBJNR = LT_OBJ-OBJNR
        I_SPRAS = SY-LANGU
      IMPORTING
        E_SYSST = GT_STAT-STTXT.
    APPEND GT_STAT.
  ENDLOOP.
  SORT GT_STAT BY AUFNR.
ENDFORM.                    "PREFETCH_STATUS

*&---------------------------------------------------------------------*
*&      Form  PREFETCH_MILL
*&---------------------------------------------------------------------*
*   1 SELECT bulk AFPO (ganti full scan per order untuk combine order).
*----------------------------------------------------------------------*
FORM PREFETCH_MILL.
  REFRESH GT_MILL.
  IF IT_AUFNR[] IS INITIAL.
    RETURN.
  ENDIF.
  SELECT AUFNR MILL_OC_AUFNR_U INTO TABLE GT_MILL
    FROM AFPO
    FOR ALL ENTRIES IN IT_AUFNR
    WHERE MILL_OC_AUFNR_U = IT_AUFNR-AUFNR.
  SORT GT_MILL BY PARENT.
ENDFORM.                    "PREFETCH_MILL

*&---------------------------------------------------------------------*
*&      Form  GET_STATUS_CACHED
*&---------------------------------------------------------------------*
FORM GET_STATUS_CACHED USING P_AUFNR CHANGING P_STAT.
  CLEAR P_STAT.
  READ TABLE GT_STAT WITH KEY AUFNR = P_AUFNR BINARY SEARCH.
  IF SY-SUBRC = 0.
    P_STAT = GT_STAT-STTXT.
  ENDIF.
ENDFORM.                    "GET_STATUS_CACHED

*&---------------------------------------------------------------------*
*&      Form  REFRESH
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*   P_FRESH = 'X' -> baca status fresh (dipanggil setelah TECO).
*   P_FRESH = space -> pakai status cache (belum TECO).
FORM REFRESH USING P_FRESH.
  DATA: LT_AFKO TYPE STANDARD TABLE OF TY_AFKO WITH HEADER LINE,
        LT_MAKT TYPE STANDARD TABLE OF TY_MAKT WITH HEADER LINE,
        LT_MATN TYPE STANDARD TABLE OF TY_MATN WITH HEADER LINE.

  IF ITAB[] IS INITIAL.
    RETURN.
  ENDIF.

  "AFKO massal (driver = ITAB, sudah 1 baris per order)
  SELECT AUFNR GAMNG GMEIN GSTRP GLTRP INTO TABLE LT_AFKO
    FROM AFKO
    FOR ALL ENTRIES IN ITAB
    WHERE AUFNR = ITAB-AUFNR.
  SORT LT_AFKO BY AUFNR.

  "MAKT massal (driver = MATNR distinct)
  LOOP AT ITAB.
    LT_MATN-MATNR = ITAB-MATNR.
    APPEND LT_MATN.
  ENDLOOP.
  SORT LT_MATN BY MATNR.
  DELETE ADJACENT DUPLICATES FROM LT_MATN COMPARING MATNR.
  IF LT_MATN[] IS NOT INITIAL.
    SELECT MATNR MAKTX INTO TABLE LT_MAKT
      FROM MAKT
      FOR ALL ENTRIES IN LT_MATN
      WHERE SPRAS = SY-LANGU
        AND MATNR = LT_MATN-MATNR.
    SORT LT_MAKT BY MATNR.
  ENDIF.

  DESCRIBE TABLE ITAB LINES V_TFILL.
  LOOP AT ITAB.
    PERFORM SET_INDICATOR USING SY-TABIX V_TFILL C_STEP_REFRESH C_TOTAL_STEP
                                'Memperbarui status & data order...'.
    CLEAR V_ORD_STAT.

    READ TABLE LT_AFKO WITH KEY AUFNR = ITAB-AUFNR BINARY SEARCH.
    IF SY-SUBRC = 0.
      ITAB-TARGET = LT_AFKO-GAMNG.
      ITAB-MEINS  = LT_AFKO-GMEIN.
      ITAB-START  = LT_AFKO-GSTRP.
      ITAB-END    = LT_AFKO-GLTRP.
    ENDIF.

    ITAB-TARGET2 = ITAB-TARGET.
    CONDENSE ITAB-TARGET2 NO-GAPS.

    READ TABLE LT_MAKT WITH KEY MATNR = ITAB-MATNR BINARY SEARCH.
    IF SY-SUBRC = 0.
      ITAB-MAKTX = LT_MAKT-MAKTX.
    ENDIF.

    PERFORM GET_GROUP USING ITAB-AUART CHANGING ITAB-GRUP.

    IF P_FRESH = 'X'.
      PERFORM GET_ORDER_STATUS USING ITAB-AUFNR CHANGING V_ORD_STAT.
    ELSE.
      PERFORM GET_STATUS_CACHED USING ITAB-AUFNR CHANGING V_ORD_STAT.
    ENDIF.
    ITAB-STATUS = V_ORD_STAT.

    IF ITAB-INDC IS INITIAL.
      ITAB-INDC = GREY.
    ENDIF.

    MODIFY ITAB.
    CLEAR ITAB.
  ENDLOOP.
ENDFORM.                    "REFRESH

*&---------------------------------------------------------------------*
*&      Form  TECO
*&---------------------------------------------------------------------*
*       Fix #1: deteksi error TECO via TABLES DETAIL_RETURN (bukan
*               header line dari IMPORTING RETURN yang selalu kosong).
*       Fix #2: ROLLBACK bersyarat bila ada error, agar order gagal
*               tidak ikut ter-commit oleh order sukses berikutnya.
*----------------------------------------------------------------------*
FORM TECO.
  DATA: LT_DETAIL_RETURN LIKE STANDARD TABLE OF BAPI_ORDER_RETURN WITH HEADER LINE.
  DATA: L_HAS_ERROR(1) TYPE C.
  DATA: L_MESS TYPE C LENGTH 220.
  DATA: L_WPMAX LIKE BAPI_ORDER_CNTRL_PARAM-WORK_PROC_MAX.
  DATA: L_OK     TYPE C.
  DATA: L_REASON TYPE C LENGTH 100.

  L_WPMAX = 99.   "eksekusi nyata (test run tidak memanggil BAPI)

  DESCRIBE TABLE ITAB LINES V_TFILL.
  LOOP AT ITAB.
    PERFORM SET_INDICATOR USING SY-TABIX V_TFILL C_STEP_TECO C_TOTAL_STEP
                                'Proses TECO order...'.
    CLEAR: TECOORDER, IT_RETURN, LT_DETAIL_RETURN, L_HAS_ERROR, L_MESS.
    REFRESH: TECOORDER, IT_RETURN, LT_DETAIL_RETURN.

    IF ITAB-STATUS CP '*REL*'.
      TECOORDER-ORDER_NUMBER = ITAB-AUFNR.
      APPEND TECOORDER.
    ENDIF.

    LOOP AT IT_AUFNR WHERE COMB_ORD EQ ITAB-AUFNR.
      CLEAR V_ORD_STAT.
      PERFORM GET_STATUS_CACHED USING IT_AUFNR-AUFNR CHANGING V_ORD_STAT.
      IF V_ORD_STAT CP '*REL*'.
        TECOORDER-ORDER_NUMBER = IT_AUFNR-AUFNR.
        APPEND TECOORDER.
      ENDIF.
    ENDLOOP.

    IF TECOORDER[] IS INITIAL.
      CONTINUE.
    ENDIF.

    IF P_TEST = 'X'.
      "=== TEST RUN: simulasi via cek status, TIDAK panggil BAPI (aman) ===
      CLEAR: L_HAS_ERROR, L_MESS.
      LOOP AT TECOORDER.
        CLEAR: L_OK, L_REASON, V_OBJNR.
        SELECT SINGLE OBJNR INTO V_OBJNR FROM AUFK
          WHERE AUFNR = TECOORDER-ORDER_NUMBER.
        PERFORM CHECK_TECO_ELIGIBLE USING V_OBJNR
                                    CHANGING L_OK L_REASON.
        IF L_OK IS INITIAL.
          L_HAS_ERROR = 'X'.
          IF L_MESS IS INITIAL.
            L_MESS = L_REASON.
          ENDIF.
        ENDIF.
      ENDLOOP.
      IF L_HAS_ERROR = 'X'.
        CONCATENATE 'TEST RUN (tidak lolos):' L_MESS INTO ITAB-MESS SEPARATED BY SPACE.
        ITAB-ERR   = 'X'.
        ITAB-INDC  = ERROR.
      ELSE.
        ITAB-MESS  = 'TEST RUN: order memenuhi syarat TECO (simulasi)'.
        ITAB-INDC  = WARNING.
      ENDIF.
    ELSE.
      "=== TRANSAKSI NYATA: panggil BAPI ===
      CALL FUNCTION 'BAPI_PROCORD_COMPLETE_TECH'
        EXPORTING
          SCOPE_COMPL_TECH   = '1'
          WORK_PROCESS_GROUP = 'COWORK_BAPI'
          WORK_PROCESS_MAX   = L_WPMAX
        IMPORTING
          RETURN             = IT_RETURN
        TABLES
          ORDERS             = TECOORDER
          DETAIL_RETURN      = LT_DETAIL_RETURN.

      "--- cek RETURN global (error umum BAPI) ---
      IF IT_RETURN-TYPE = 'E' OR IT_RETURN-TYPE = 'A'.
        L_HAS_ERROR = 'X'.
        L_MESS = IT_RETURN-MESSAGE.
      ENDIF.

      "--- cek DETAIL_RETURN per-order ---
      LOOP AT LT_DETAIL_RETURN WHERE TYPE = 'E' OR TYPE = 'A'.
        L_HAS_ERROR = 'X'.
        IF L_MESS IS INITIAL.
          L_MESS = LT_DETAIL_RETURN-MESSAGE.
        ENDIF.
      ENDLOOP.

      IF L_HAS_ERROR = 'X'.
        CONCATENATE 'Teco Orders: ' L_MESS INTO ITAB-MESS SEPARATED BY SPACE.
        ITAB-ERR    = 'X'.
        ITAB-INDC  = ERROR.
        PERFORM ROLLBACK.
      ELSE.
        ITAB-INDC  = SUCCES.
        PERFORM COMMIT.
      ENDIF.
    ENDIF.

    MODIFY ITAB.
    CLEAR ITAB.
  ENDLOOP.
ENDFORM.                    "TECO

*&---------------------------------------------------------------------*
*&      Form  ROLLBACK
*&---------------------------------------------------------------------*
*       Fix #2: rollback LUW saat TECO order gagal, supaya perubahan
*       parsial tidak ikut ter-commit oleh COMMIT WORK order lain.
*----------------------------------------------------------------------*
FORM ROLLBACK.
  CALL FUNCTION 'BAPI_TRANSACTION_ROLLBACK'.
  CALL FUNCTION 'DEQUEUE_ALL'
    EXPORTING
      _SYNCHRON = 'X'.
ENDFORM.                    "ROLLBACK

*&---------------------------------------------------------------------*
*&      Form  CHECK_TECO_ELIGIBLE
*&---------------------------------------------------------------------*
*   Simulasi Test Run tanpa BAPI: cek apakah order boleh di-TECO
*   berdasarkan status management (read-only, aman).
*   P_OK = 'X' bila lolos, P_REASON = alasan bila tidak.
*   Status internal: REL=I0002, TECO=I0045, CLSD=I0046,
*                    DLFL=I0076, LKD=I0043.
*----------------------------------------------------------------------*
FORM CHECK_TECO_ELIGIBLE USING P_OBJNR CHANGING P_OK P_REASON.
  CLEAR: P_OK, P_REASON.

  IF P_OBJNR IS INITIAL.
    P_REASON = 'OBJNR order tidak ditemukan'.
    RETURN.
  ENDIF.

  "1. REL wajib aktif
  CALL FUNCTION 'STATUS_CHECK'
    EXPORTING
      OBJNR             = P_OBJNR
      STATUS            = 'I0002'
    EXCEPTIONS
      OBJECT_NOT_FOUND  = 1
      STATUS_NOT_ACTIVE = 2
      OTHERS            = 3.
  IF SY-SUBRC = 1.
    P_REASON = 'Order tidak ditemukan'.
    RETURN.
  ELSEIF SY-SUBRC <> 0.
    P_REASON = 'Status bukan Released (REL)'.
    RETURN.
  ENDIF.

  "2. TECO tidak boleh sudah aktif
  CALL FUNCTION 'STATUS_CHECK'
    EXPORTING
      OBJNR             = P_OBJNR
      STATUS            = 'I0045'
    EXCEPTIONS
      OBJECT_NOT_FOUND  = 1
      STATUS_NOT_ACTIVE = 2
      OTHERS            = 3.
  IF SY-SUBRC = 0.
    P_REASON = 'Order sudah berstatus TECO'.
    RETURN.
  ENDIF.

  "3. CLSD tidak boleh aktif
  CALL FUNCTION 'STATUS_CHECK'
    EXPORTING
      OBJNR             = P_OBJNR
      STATUS            = 'I0046'
    EXCEPTIONS
      OBJECT_NOT_FOUND  = 1
      STATUS_NOT_ACTIVE = 2
      OTHERS            = 3.
  IF SY-SUBRC = 0.
    P_REASON = 'Order sudah Closed (CLSD)'.
    RETURN.
  ENDIF.

  "4. Deletion Flag tidak boleh aktif
  CALL FUNCTION 'STATUS_CHECK'
    EXPORTING
      OBJNR             = P_OBJNR
      STATUS            = 'I0076'
    EXCEPTIONS
      OBJECT_NOT_FOUND  = 1
      STATUS_NOT_ACTIVE = 2
      OTHERS            = 3.
  IF SY-SUBRC = 0.
    P_REASON = 'Order punya Deletion Flag (DLFL)'.
    RETURN.
  ENDIF.

  "5. LKD (terkunci) tidak boleh aktif
  CALL FUNCTION 'STATUS_CHECK'
    EXPORTING
      OBJNR             = P_OBJNR
      STATUS            = 'I0043'
    EXCEPTIONS
      OBJECT_NOT_FOUND  = 1
      STATUS_NOT_ACTIVE = 2
      OTHERS            = 3.
  IF SY-SUBRC = 0.
    P_REASON = 'Order terkunci (LKD)'.
    RETURN.
  ENDIF.

  P_OK     = 'X'.
  P_REASON = 'Memenuhi syarat TECO'.
ENDFORM.                    "CHECK_TECO_ELIGIBLE

*&---------------------------------------------------------------------*
*&      Form  SEND_EMAIL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM SEND_EMAIL.
  DATA : SUBJECT_EMAIL(50).
  DATA : LX_BCS TYPE REF TO CX_BCS,
         LV_ERR TYPE STRING.

  CLEAR : W_TEXT.
  REFRESH : I_TEXT.

  CONCATENATE 'Status Process Order' SY-DATUM+4(2)'-' SY-DATUM+0(4) INTO SUBJECT_EMAIL SEPARATED BY SPACE.

  LO_SEND_REQUEST = CL_BCS=>CREATE_PERSISTENT( ).
*--Message body and subject
  W_TEXT-LINE = 'Dear All,'.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  CONCATENATE '' '' INTO W_TEXT-LINE SEPARATED BY CL_ABAP_CHAR_UTILITIES=>NEWLINE.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  CONCATENATE 'Berikut terlampir data PRO yang terdapat movement di bulan' SY-DATUM+4(2) '-' SY-DATUM+0(4) 'dan telah dilakukan TECO' INTO W_TEXT-LINE SEPARATED BY SPACE.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  CONCATENATE '' '' INTO W_TEXT-LINE SEPARATED BY CL_ABAP_CHAR_UTILITIES=>NEWLINE.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  W_TEXT-LINE = 'Best Regards,'.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  CONCATENATE '' '' INTO W_TEXT-LINE SEPARATED BY CL_ABAP_CHAR_UTILITIES=>NEWLINE.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

  W_TEXT-LINE = SY-UNAME.
  APPEND W_TEXT TO I_TEXT.
  CLEAR W_TEXT.

*  W_TEXT-LINE = 'Please find enclosed herewith the attached file.'.
*  APPEND W_TEXT TO I_TEXT.
*  CLEAR W_TEXT.

  LO_DOCUMENT = CL_DOCUMENT_BCS=>CREATE_DOCUMENT( "create document
  I_TYPE = 'TXT' "TYPE OF DOCUMENT HTM, TXT ETC
  I_TEXT =  I_TEXT "email body internal table
  I_SUBJECT = SUBJECT_EMAIL ). "email subject here p_sub input parameter
* Pass the document to send request
  LO_SEND_REQUEST->SET_DOCUMENT( LO_DOCUMENT ).

  "GENERATE FORMAT TO EXCEL
  CLEAR: LV_DATA_STRING, LV_STRING.

*  LV_DATA_STRING = 'FRSED23B'.
  CONCATENATE 'Indicator' 'Order' 'Material' 'Order Type' 'Grup' 'Plant' 'Target Qty' 'Unit' 'Basic Start' 'Basic Finish' 'System Status' 'Material Description' 'Message'
               INTO LV_STRING SEPARATED BY ','.

  CONCATENATE LV_DATA_STRING LV_STRING INTO LV_DATA_STRING SEPARATED BY CL_ABAP_CHAR_UTILITIES=>NEWLINE.

  LOOP AT ITAB.
    CONCATENATE ITAB-INDC ITAB-AUFNR ITAB-MATNR ITAB-AUART ITAB-GRUP ITAB-WERKS ITAB-TARGET2 ITAB-MEINS ITAB-START ITAB-END ITAB-STATUS ITAB-MAKTX ITAB-MESS
                INTO LV_STRING SEPARATED BY ','.
    CONCATENATE LV_DATA_STRING LV_STRING INTO LV_DATA_STRING SEPARATED BY CL_ABAP_CHAR_UTILITIES=>NEWLINE.
  ENDLOOP.

**Convert string to xstring
  CALL FUNCTION 'HR_KR_STRING_TO_XSTRING'
    EXPORTING
      CODEPAGE_TO      = '4110'
      UNICODE_STRING   = LV_DATA_STRING
*     OUT_LEN          =
    IMPORTING
      XSTRING_STREAM   = LV_XSTRING
    EXCEPTIONS
      INVALID_CODEPAGE = 1
      INVALID_STRING   = 2
      OTHERS           = 3.
  IF SY-SUBRC <> 0.
    IF SY-SUBRC = 1 .

    ELSEIF SY-SUBRC = 2 .
      MESSAGE 'Invalid string saat konversi data' TYPE 'S' DISPLAY LIKE 'E'.
    ENDIF.
  ENDIF.

  CLEAR : LIT_BINARY_CONTENT.
  REFRESH : LIT_BINARY_CONTENT.

***Xstring to binary
  CALL FUNCTION 'SCMS_XSTRING_TO_BINARY'
    EXPORTING
      BUFFER     = LV_XSTRING
    TABLES
      BINARY_TAB = LIT_BINARY_CONTENT.
**add attachment
  CLEAR L_ATTSUBJECT .
  "CONCATENATE 'FESTA Stock' S_CPUDT-HIGH INTO L_ATTSUBJECT SEPARATED BY SPACE.
  L_ATTSUBJECT = 'TECO Result'.
* Create Attachment
  TRY.
      LO_DOCUMENT->ADD_ATTACHMENT( EXPORTING
                                    I_ATTACHMENT_TYPE = 'CSV'
                                    I_ATTACHMENT_SUBJECT = L_ATTSUBJECT
                                    I_ATT_CONTENT_HEX = LIT_BINARY_CONTENT  ).
    CATCH CX_BCS INTO LX_BCS.
      LV_ERR = LX_BCS->GET_TEXT( ).
      CONCATENATE 'Attachment gagal:' LV_ERR INTO LV_ERR SEPARATED BY SPACE.
      MESSAGE LV_ERR TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.

  "SET SENDER + RECIPIENT + SEND dalam satu TRY/CATCH (hindari short dump)
  TRY.
      "Sender
      LO_SENDER = CL_SAPUSER_BCS=>CREATE( SY-UNAME ).
      LO_SEND_REQUEST->SET_SENDER( I_SENDER = LO_SENDER ).

      "Recipient TO
      IF PA_TO IS NOT INITIAL.
        LOOP AT PA_TO.
          CLEAR LO_RECIPIENT.
          LO_RECIPIENT = CL_CAM_ADDRESS_BCS=>CREATE_INTERNET_ADDRESS( PA_TO-LOW ).
          LO_SEND_REQUEST->ADD_RECIPIENT( I_RECIPIENT = LO_RECIPIENT ).
        ENDLOOP.
      ENDIF.

      "Recipient CC
      IF PA_CC IS NOT INITIAL.
        LOOP AT PA_CC.
          CLEAR LO_RECIPIENT.
          LO_RECIPIENT = CL_CAM_ADDRESS_BCS=>CREATE_INTERNET_ADDRESS( PA_CC-LOW ).
          LO_SEND_REQUEST->ADD_RECIPIENT( I_RECIPIENT = LO_RECIPIENT
                                          I_COPY      = 'X' ).
        ENDLOOP.
      ENDIF.

      "Recipient BCC
      IF PA_BCC IS NOT INITIAL.
        LOOP AT PA_BCC.
          CLEAR LO_RECIPIENT.
          LO_RECIPIENT = CL_CAM_ADDRESS_BCS=>CREATE_INTERNET_ADDRESS( PA_BCC-LOW ).
          LO_SEND_REQUEST->ADD_RECIPIENT( I_RECIPIENT  = LO_RECIPIENT
                                          I_BLIND_COPY = 'X' ).
        ENDLOOP.
      ENDIF.

      "Send email
      LO_SEND_REQUEST->SEND( I_WITH_ERROR_SCREEN = 'X' ).
      COMMIT WORK.
      MESSAGE 'Email hasil TECO berhasil dikirim' TYPE 'S' DISPLAY LIKE 'E'.

    CATCH CX_BCS INTO LX_BCS.
      LV_ERR = LX_BCS->GET_TEXT( ).
      CONCATENATE 'Email gagal:' LV_ERR INTO LV_ERR SEPARATED BY SPACE.
      MESSAGE LV_ERR TYPE 'S' DISPLAY LIKE 'E'.
  ENDTRY.
ENDFORM.                    "SEND_EMAIL
*&---------------------------------------------------------------------*
*&      Form  COMMIT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM COMMIT.
  CALL FUNCTION 'DB_COMMIT'.
  CALL FUNCTION 'DEQUEUE_ALL'
    EXPORTING
      _SYNCHRON = 'X'.
  COMMIT WORK AND WAIT.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      WAIT = 'X'.
ENDFORM.                    "TECO
*&---------------------------------------------------------------------*
*&      Form  GET_ORDER_STATUS
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->ORDER      text
*      -->STAT       text
*----------------------------------------------------------------------*
FORM GET_ORDER_STATUS USING ORDER CHANGING STAT.
  CLEAR: V_OBJNR.

  SELECT SINGLE OBJNR INTO V_OBJNR FROM AUFK WHERE AUFNR = ORDER.

  CALL FUNCTION 'AIP9_STATUS_READ'
    EXPORTING
      I_OBJNR = V_OBJNR
      I_SPRAS = SY-LANGU
    IMPORTING
      E_SYSST = STAT.
ENDFORM.                    "GET_ORDER_STATUS
*&---------------------------------------------------------------------*
*&      Form  BAPI_COMMIT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM BAPI_COMMIT .
  CALL FUNCTION 'DB_COMMIT'.
  CALL FUNCTION 'DEQUEUE_ALL'
    EXPORTING
      _SYNCHRON = 'X'.
  COMMIT WORK AND WAIT.

  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      WAIT = 'X'.
ENDFORM.                    "BAPI_COMMIT

*&---------------------------------------------------------------------*
*&      Form  SET_CELL_COLOURS
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->COLUMN_NAME  text
*      -->REMARK       text
*----------------------------------------------------------------------*
FORM SET_CELL_COLOURS TABLES CELL_COLOUR USING COLUMN_NAME COLOR .
  WA_CELL_COLOR-FNAME = COLUMN_NAME.
  WA_CELL_COLOR-COLOR-COL = COLOR.  "Yellow, Range: 1-7
  WA_CELL_COLOR-COLOR-INT = 1.
  WA_CELL_COLOR-COLOR-INV = 1.
  APPEND WA_CELL_COLOR TO CELL_COLOUR.
  CLEAR: WA_CELL_COLOR.
ENDFORM.                    "SET_CELL_COLOURS

*&---------------------------------------------------------------------*
*&      Form  DISPLAY_ALV
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM DISPLAY_ALV.
  PERFORM F_FIELD_CATALOG_PREVIEW.
  PERFORM F_LAYOUT.
  PERFORM F_LIST_DETAIL_PREVIEW.
ENDFORM.                    "DISPLAY_alv

*&---------------------------------------------------------------------*
*&      Form  F_FIELD_CATALOG_PREVIEW
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM F_FIELD_CATALOG_PREVIEW.
  CLEAR T_FIELDCAT.
  REFRESH: T_FIELDCAT.
  PERFORM F_ALV_FIELDCATG_ICON USING 'ITAB' :
    'INDC'            'X' 'X'  '' '8'    'Indicator'              '' '' '' '',
    'AUFNR'           ''  'X'  '' '12'   'Order Number'           '' '' '' '',
    'AUART'           ''  'X'  '' '8'    'Order Type'             '' '' '' '',
    'GRUP'            ''  'X'  '' '14'   'Grup'                   '' '' '' '',
    'MATNR'           ''  'X'  '' '18'   'Material'               '' '' '' '',
    'MAKTX'           ''  ''   '' '30'   'Material Desc'          '' '' '' '',
    'WERKS'           ''  'X'  '' '6'    'Plant'                  '' '' '' '',
    'ERDAT'           ''  'X'  '' '10'   'Created On'             '' '' '' '',
    'STATUS'          ''  ''   '' '18'   'Status Order'           '' '' '' '',
    'MESS'            ''  ''   '' '60'   'Message'                '' '' '' ''.

  T_FIELDCAT-NO_ZERO = ''.
  MODIFY T_FIELDCAT TRANSPORTING NO_ZERO WHERE FIELDNAME EQ 'AUFNR'.

  T_FIELDCAT-JUST = 'C'.
  MODIFY T_FIELDCAT TRANSPORTING JUST WHERE FIELDNAME NE 'MESS'.

ENDFORM.                    "F_FIELD_CATALOG_PREVIEW

*&---------------------------------------------------------------------*
*&      Form  F_LAYOUT_PREVIEW
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM F_LAYOUT.
  CLEAR WA_LAYOUT.
  WA_LAYOUT-ZEBRA                 = 'X'.
  WA_LAYOUT-CONFIRMATION_PROMPT   = ''.
  WA_LAYOUT-SUBTOTALS_TEXT        = 'Sub Total'.
  WA_LAYOUT-TOTALS_TEXT           = 'Total'.
  WA_LAYOUT-BOX_FIELDNAME         = 'BOX'.
  WA_LAYOUT-CELL_MERGE            = 'X'.
  WA_LAYOUT-INFO_FIELDNAME        = 'LINE_COLOR'.
  WA_LAYOUT-COLTAB_FIELDNAME      = 'CELL_COLOR'.
ENDFORM.                    "F_LAYOUT_PREVIEW

*&---------------------------------------------------------------------*
*&      Form  F_LIST_DETAIL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM F_LIST_DETAIL_PREVIEW.
  DATA: LWA_SORT  TYPE LVC_S_SORT.

  D_REPID = SY-REPID.
  T_PRINT-NO_PRINT_LISTINFOS = 'X'.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      I_CALLBACK_PROGRAM       = D_REPID
      I_CALLBACK_USER_COMMAND  = 'F_USER_COMMAND'
      I_CALLBACK_PF_STATUS_SET = 'F_GUI_STATUS'
      IS_LAYOUT                = WA_LAYOUT
      IT_FIELDCAT              = T_FIELDCAT[]
      IT_EVENTS                = T_EVENTS[]
      I_DEFAULT                = 'X'
      I_SAVE                   = 'A'
      IS_VARIANT               = WA_VARIANTE
      IS_PRINT                 = T_PRINT
      IT_SORT                  = T_SORT[]
      IT_EXCLUDING             = T_EXCLUDING[]
      I_BYPASSING_BUFFER       = 'X'
    TABLES
      T_OUTTAB                 = ITAB
    EXCEPTIONS
      PROGRAM_ERROR            = 1
      OTHERS                   = 2.
ENDFORM.                    " f_list_detail


*&---------------------------------------------------------------------
*&      Form  F_GUI_STATUS
*&---------------------------------------------------------------------
FORM F_GUI_STATUS USING FT_EXTAB TYPE SLIS_T_EXTAB.
  DATA: LT_FCODE TYPE TABLE OF SY-UCOMM.

  SET PF-STATUS 'COHVPI'.
  SET TITLEBAR  'COHVPI'.
ENDFORM.                    " F_ALV_STATUS


*&---------------------------------------------------------------------*
*&      Form  F_USER_COMMAND
*&---------------------------------------------------------------------*
FORM F_USER_COMMAND USING FU_UCOMM LIKE SY-UCOMM
                          FU_SELFIELD TYPE SLIS_SELFIELD.

  CASE FU_UCOMM.
    WHEN 'EXEC'.
      "Eksekusi TECO dari ALV hanya di mode Transaksi
      IF RB1 = 'X'.
        PERFORM TECO.
        PERFORM REFRESH USING 'X'.
        IF P_TEST IS INITIAL.
          PERFORM SEND_EMAIL.
        ENDIF.
      ENDIF.
  ENDCASE.

  FU_SELFIELD-REFRESH = 'X'.

ENDFORM.                    "F_USER_COMMAND

*&---------------------------------------------------------------------*
*&      Form  SET_INDICATOR
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->INDEX          text
*      -->COUNT_INDEX    text
*      -->PROCESS        text
*      -->COUNT_PROCESS  text
*      -->TEXT           text
*----------------------------------------------------------------------*
FORM SET_INDICATOR USING INDEX COUNT_INDEX PROCESS COUNT_PROCESS TEXT.
  DATA: PERCENT       TYPE P,
        L_COUNT_INDEX TYPE I.
  CLEAR: PERCENT.

  IF BACK EQ 'X'.
    EXIT.
  ENDIF.

  "Pengaman: hindari division by zero bila tabel sumber kosong (COUNT_INDEX = 0)
  L_COUNT_INDEX = COUNT_INDEX.
  IF L_COUNT_INDEX = 0.
    L_COUNT_INDEX = 1.
  ENDIF.

  PERCENT = ( ( INDEX + ( L_COUNT_INDEX * PROCESS ) - L_COUNT_INDEX ) / ( L_COUNT_INDEX * COUNT_PROCESS ) ) * 100.

  CALL FUNCTION 'SAPGUI_PROGRESS_INDICATOR'
    EXPORTING
      PERCENTAGE = PERCENT
      TEXT       = TEXT.
ENDFORM.                    "SET_INDICATOR


*&---------------------------------------------------------------------*
*&      Form  CONVERSION_INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->INPUT      text
*      -->OUTPUT     text
*----------------------------------------------------------------------*
FORM CONVERSION_INPUT USING INPUT CHANGING OUTPUT.
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
    EXPORTING
      INPUT  = INPUT
    IMPORTING
      OUTPUT = OUTPUT.
ENDFORM.                    "CONVERSION_INPUT

*&---------------------------------------------------------------------*
*&      Form  CONVERSION_OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->INPUT      text
*      -->OUTPUT     text
*----------------------------------------------------------------------*
FORM CONVERSION_OUTPUT USING INPUT CHANGING OUTPUT.
  CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
    EXPORTING
      INPUT  = INPUT
    IMPORTING
      OUTPUT = OUTPUT.
ENDFORM.                    "CONVERSION_OUTPUT