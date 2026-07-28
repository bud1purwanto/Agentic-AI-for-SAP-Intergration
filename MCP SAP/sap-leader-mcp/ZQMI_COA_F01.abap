*&---------------------------------------------------------------------*
*&  Include           ZQMI_CERTIFICATE_F01
*&---------------------------------------------------------------------*
INITIALIZATION.
  MOVE 'Program Information' TO INFO.

* Cache format MIC dari master QPMK: decimal places (STELLEN) + unit, per MIC
* dan per plant. Dibaca sekali per kombinasi lalu dilayani dari memori.
* Dinamis penuh - MIC baru otomatis ikut tanpa perlu ubah kode.
TYPES: BEGIN OF TY_MICFMT,
         MKMNR   TYPE QPMK-MKMNR,
         WERKS   TYPE QPMK-WERKS,
         STELLEN TYPE QPMK-STELLEN,
         UOM     TYPE QPMK-MASSEINHSW,
       END OF TY_MICFMT.
DATA: GT_MICFMT TYPE TABLE OF TY_MICFMT,
      GS_MICFMT TYPE TY_MICFMT.
DATA: GV_DEC TYPE I,
      GV_UOM TYPE QPMK-MASSEINHSW.

* Cache hasil rata-rata JR per mother roll (enhancement 18/07/2026).
TYPES: BEGIN OF TY_JRAVG,
         INSLOT TYPE QALS-PRUEFLOS,
         MIC    TYPE QAMV-VERWMERKM,
         ISJR   TYPE C,
         VAL    TYPE QAMR-MITTELWERT,
         CNT    TYPE I,
       END OF TY_JRAVG.
DATA: GT_JRAVG TYPE TABLE OF TY_JRAVG,
      GS_JRAVG TYPE TY_JRAVG.

AT SELECTION-SCREEN.
  IF SY-UCOMM = 'INFO'.
    PERFORM F_PROG_INFO USING V_PROG.
  ENDIF.

INITIALIZATION.
  CALL FUNCTION 'CONVERSION_EXIT_ATINN_INPUT' EXPORTING INPUT = 'ZZNOMORROLL' IMPORTING OUTPUT = ATINN_ROLL.
  CALL FUNCTION 'CONVERSION_EXIT_ATINN_INPUT' EXPORTING INPUT = 'ZZCODE' IMPORTING OUTPUT = ATINN_CODE.

START-OF-SELECTION.
  IF P_VBELN IS INITIAL.
    MESSAGE 'Nomor ODO (Delivery) WAJIB diisi! Meski ingin filter by Batch/Roll, ODO tetap wajib diisi agar SAP tidak Time-Out.' TYPE 'I'.
  ELSE.
    PERFORM GET_DATA.
    SORT IT_DATA BY VBELN CHARG NUMMIC NUM ASCENDING CHK DESCENDING.
    CALL SCREEN 0100.
  ENDIF.

*&---------------------------------------------------------------------*
*&      Form  get_data
*&----------------------------------------------------AAA-----------------*
*       text
*----------------------------------------------------------------------*
FORM GET_DATA.
  DATA : TEXT1 TYPE C LENGTH 25,
         TEXT2 TYPE C LENGTH 30,
         INSPOPER TYPE BAPI2045L2-INSPOPER,
         ROLL TYPE C LENGTH 10,
         LV_KUNNR LIKE ZMAP_COA-KUNNR.
  DATA : R_PSTYV TYPE RANGE OF LIPS-PSTYV,
         WA_PSTYV LIKE LINE OF R_PSTYV,
         IT_ZMAP_DELIV TYPE STANDARD TABLE OF ZMAP_TYPE WITH HEADER LINE.

  CLEAR : TEXT1, TEXT2,ROLL, R_PSTYV, IT_ZMAP_DELIV.
  REFRESH : R_PSTYV, IT_ZMAP_DELIV.

  SELECT PROG TYPE VALUE INTO CORRESPONDING FIELDS OF TABLE IT_ZMAP_DELIV FROM ZMAP_TYPE
    WHERE PROG = SY-CPROG AND TYPE = 'ITEM CATEGORY'.
  LOOP AT IT_ZMAP_DELIV.
    WA_PSTYV-SIGN = 'I'.
    WA_PSTYV-OPTION = 'EQ'.
    WA_PSTYV-LOW = IT_ZMAP_DELIV-VALUE.
    APPEND WA_PSTYV TO R_PSTYV.
  ENDLOOP.
  IF R_PSTYV[] IS INITIAL.
    WA_PSTYV-SIGN = 'I'. WA_PSTYV-OPTION = 'EQ'. WA_PSTYV-LOW = 'ZB'. APPEND WA_PSTYV TO R_PSTYV.
  ENDIF.

  IF P_CHARG IS INITIAL AND P_ATWRT IS NOT INITIAL.


    SELECT OBJEK INTO WA_OBJEK-OBJEK
      FROM  AUSP
      WHERE AUSP~ATINN = ATINN_ROLL
      AND AUSP~ATWRT IN P_ATWRT"-LOW "= '4 PEE 5 010103'
      %_HINTS ORACLE 'INDEX("AUSP~N1")'.
      APPEND WA_OBJEK TO IT_OBJEK.
    ENDSELECT.

    IF IT_OBJEK[] IS NOT INITIAL.
      " Extract unique CHARG to fetch LIPS
      DATA: IT_CHARG_TMP LIKE TABLE OF WA_OBJEK WITH HEADER LINE.
      IT_CHARG_TMP[] = IT_OBJEK[].
      LOOP AT IT_OBJEK INTO WA_OBJEK.
        SELECT SINGLE INOB~OBJEK INTO WA_OBJEK-IOBJEK
        FROM  INOB
        WHERE CUOBJ = WA_OBJEK-OBJEK.
        SPLIT WA_OBJEK-IOBJEK AT SPACE INTO TEXT1 TEXT2.
        CONDENSE: TEXT1,TEXT2.
        WA_OBJEK-OBJ = TEXT1.
        WA_OBJEK-CHARG = TEXT2.
        MODIFY IT_OBJEK FROM WA_OBJEK.
      ENDLOOP.

      IF IT_OBJEK[] IS NOT INITIAL.
        SELECT VBELN POSNR CHARG MATNR WERKS UECHA
          INTO CORRESPONDING FIELDS OF TABLE IT_DATA
          FROM LIPS
          FOR ALL ENTRIES IN IT_OBJEK
          WHERE VBELN IN P_VBELN
            AND POSNR IN P_POSNR
            AND MATNR IN P_MATNR
            AND CHARG = IT_OBJEK-CHARG
            AND PSTYV IN R_PSTYV.

        IF P_POSNR-LOW IS NOT INITIAL.
          SELECT VBELN POSNR CHARG MATNR WERKS UECHA
            APPENDING CORRESPONDING FIELDS OF TABLE IT_DATA
            FROM LIPS
            FOR ALL ENTRIES IN IT_OBJEK
            WHERE VBELN IN P_VBELN
              AND UECHA IN P_POSNR
              AND MATNR IN P_MATNR
              AND CHARG = IT_OBJEK-CHARG
              AND PSTYV IN R_PSTYV.
        ENDIF.
      ENDIF.
    ENDIF.
  ELSE.
    SELECT VBELN POSNR CHARG MATNR WERKS UECHA
      INTO CORRESPONDING FIELDS OF TABLE IT_DATA
      FROM LIPS
      WHERE VBELN IN P_VBELN
        AND POSNR IN P_POSNR
        AND MATNR IN P_MATNR
        AND CHARG IN P_CHARG
        AND PSTYV IN R_PSTYV.

    IF P_POSNR-LOW IS NOT INITIAL.
      SELECT VBELN POSNR CHARG MATNR WERKS UECHA
        APPENDING CORRESPONDING FIELDS OF TABLE IT_DATA
        FROM LIPS
        WHERE VBELN IN P_VBELN
          AND UECHA IN P_POSNR
          AND MATNR IN P_MATNR
          AND CHARG IN P_CHARG
          AND PSTYV IN R_PSTYV.
    ENDIF.
  ENDIF.
  DELETE IT_DATA WHERE CHARG IS INITIAL.

  " Enhancement: Group by Material (Representative Batch)
  " SORT IT_DATA BY VBELN MATNR CHARG.
  " DELETE ADJACENT DUPLICATES FROM IT_DATA COMPARING VBELN MATNR.

  " ----------------------------------------------------------------------
  " PHASE 1 & 2: BULK CHARACTERISTIC EXTRACTION
  " ----------------------------------------------------------------------
  CLEAR IT_BATCH_COLLECT. REFRESH IT_BATCH_COLLECT.



  LOOP AT IT_DATA.
    IT_BATCH_COLLECT-MATNR = IT_DATA-MATNR.
    IT_BATCH_COLLECT-CHARG = IT_DATA-CHARG.
    APPEND IT_BATCH_COLLECT.
  ENDLOOP.

  SORT IT_BATCH_COLLECT BY MATNR CHARG.
  DELETE ADJACENT DUPLICATES FROM IT_BATCH_COLLECT COMPARING MATNR CHARG.

  CLEAR IT_INOB. REFRESH IT_INOB.
  CLEAR IT_AUSP. REFRESH IT_AUSP.
  CLEAR IT_TEMP_OBJEK. REFRESH IT_TEMP_OBJEK.

  IF IT_BATCH_COLLECT[] IS NOT INITIAL.
    LOOP AT IT_BATCH_COLLECT.
      IT_TEMP_OBJEK-OBJEK = IT_BATCH_COLLECT-MATNR.
      IT_TEMP_OBJEK-OBJEK+18(10) = IT_BATCH_COLLECT-CHARG.
      APPEND IT_TEMP_OBJEK.
    ENDLOOP.

    SELECT CUOBJ OBJEK INTO TABLE IT_INOB_RAW
      FROM INOB
      FOR ALL ENTRIES IN IT_TEMP_OBJEK
      WHERE OBJEK = IT_TEMP_OBJEK-OBJEK
        AND OBTAB = 'MCH1'.

    LOOP AT IT_INOB_RAW.
      IT_INOB-CUOBJ = IT_INOB_RAW-CUOBJ.
      IT_INOB-OBJEK = IT_INOB_RAW-CUOBJ.
      IT_INOB-MATNR = IT_INOB_RAW-OBJEK(18).
      IT_INOB-CHARG = IT_INOB_RAW-OBJEK+18(10).
      APPEND IT_INOB.
    ENDLOOP.
    SORT IT_INOB BY MATNR CHARG.
  ENDIF.

  IF IT_INOB[] IS NOT INITIAL.
    SELECT OBJEK ATINN ATWRT INTO TABLE IT_AUSP
      FROM AUSP
      FOR ALL ENTRIES IN IT_INOB
      WHERE OBJEK = IT_INOB-OBJEK
        AND ( ATINN = ATINN_ROLL OR ATINN = ATINN_CODE )
        AND KLART = '023'.
    SORT IT_AUSP BY OBJEK ATINN.
  ENDIF.

  " ----------------------------------------------------------------------
  " PHASE 3: ALV POPULATION
  " ----------------------------------------------------------------------
  LOOP AT IT_DATA.
    CLEAR: IT_DATA-NOMSR, IT_DATA-ZZTYPE.
    DATA: L_SUBRC TYPE SY-SUBRC.
    READ TABLE IT_INOB WITH KEY MATNR = IT_DATA-MATNR CHARG = IT_DATA-CHARG BINARY SEARCH.
    IF SY-SUBRC EQ 0.
      READ TABLE IT_AUSP WITH KEY OBJEK = IT_INOB-OBJEK ATINN = ATINN_ROLL BINARY SEARCH.
      IF SY-SUBRC EQ 0.
        IT_DATA-NOMSR = IT_AUSP-ATWRT.
      ENDIF.
      READ TABLE IT_AUSP WITH KEY OBJEK = IT_INOB-OBJEK ATINN = ATINN_CODE BINARY SEARCH.
      L_SUBRC = SY-SUBRC.
      IF SY-SUBRC EQ 0.
        IT_DATA-ZZTYPE = IT_AUSP-ATWRT.
      ENDIF.
    ELSE.
      L_SUBRC = 4.
    ENDIF.

    IF L_SUBRC EQ 0.
      " Edited by J. Budi (Antigravity) on 28.06.2026
      DATA: IT_ZMAP_GEN LIKE TABLE OF IT_ZMAP WITH HEADER LINE,
            IT_ZMAP_CUS LIKE TABLE OF IT_ZMAP WITH HEADER LINE.
      CLEAR : IT_ZMAP, LV_KUNNR, IT_ZMAP_GEN, IT_ZMAP_CUS.
      REFRESH: IT_ZMAP, IT_ZMAP_GEN, IT_ZMAP_CUS.
      SELECT SINGLE KUNAG INTO LV_KUNNR
        FROM LIKP
        WHERE VBELN = IT_DATA-VBELN.

      " Edited by J. Budi (Antigravity) on 28.06.2026
      SELECT MATNR MIC KUNNR METHOD MAPPING
        INTO CORRESPONDING FIELDS OF TABLE IT_ZMAP_GEN
        FROM ZMAP_COA
        WHERE MATNR    = IT_DATA-MATNR
          AND KUNNR    = ' '
          AND DELETION NE 'X'.

      IF LV_KUNNR IS NOT INITIAL.
        SELECT MATNR MIC KUNNR METHOD MAPPING
          INTO CORRESPONDING FIELDS OF TABLE IT_ZMAP_CUS
          FROM ZMAP_COA
          WHERE MATNR    = IT_DATA-MATNR
            AND KUNNR    = LV_KUNNR
            AND DELETION NE 'X'.
      ENDIF.

      IT_ZMAP[] = IT_ZMAP_GEN[].
      SORT IT_ZMAP BY MIC ASCENDING.
      LOOP AT IT_ZMAP_CUS.
        READ TABLE IT_ZMAP WITH KEY MIC = IT_ZMAP_CUS-MIC BINARY SEARCH.
        IF SY-SUBRC = 0.
          IT_ZMAP-METHOD = IT_ZMAP_CUS-METHOD.
          IT_ZMAP-KUNNR  = IT_ZMAP_CUS-KUNNR.
          IT_ZMAP-MAPPING = IT_ZMAP_CUS-MAPPING.
          MODIFY IT_ZMAP INDEX SY-TABIX.
        ELSE.
          APPEND IT_ZMAP_CUS TO IT_ZMAP.
        ENDIF.
      ENDLOOP.

      SORT IT_ZMAP BY MIC ASCENDING.
      DELETE ADJACENT DUPLICATES FROM IT_ZMAP COMPARING MIC.

      IF IT_ZMAP[] IS INITIAL.
        MESSAGE 'Material belum dimapping di ZMAP_COA. Harap lengkapi mapping terlebih dahulu!' TYPE 'S' DISPLAY LIKE 'E'.
        STOP.
      ENDIF.
    ENDIF.
    " Edited by J. Budi (Antigravity) on 28.06.2026
    PERFORM GET_TRACED_LOTS.
    PERFORM GET_MIC.

    IF IT_DATA-UECHA IS INITIAL.
      IT_DATA-UECHA = IT_DATA-POSNR.
    ENDIF.
    MODIFY IT_DATA.
  ENDLOOP.
  IT_LOT[] = IT_DATA[].
  CLEAR IT_DATA. REFRESH IT_DATA.
  SORT IT_MIC1 BY VBELN POSNR CHARG.
  LOOP AT IT_LOT.
    READ TABLE IT_MIC1 WITH KEY VBELN = IT_LOT-VBELN POSNR = IT_LOT-POSNR CHARG = IT_LOT-CHARG BINARY SEARCH.
    IF SY-SUBRC EQ 0.
      LOOP AT IT_MIC1 WHERE VBELN = IT_LOT-VBELN AND POSNR = IT_LOT-POSNR AND CHARG = IT_LOT-CHARG.
        " Enhancement (user 18/07/2026): untuk MIC mapping JR (Conv/Base),
        " nilai = rata-rata sibling roll 1 mother roll (lihat GET_JR_AVG).
        DATA: LV_ISJR TYPE C, LV_JRVAL TYPE QAMR-MITTELWERT.
        DATA: LV_JRCNT TYPE I.
        CLEAR: LV_ISJR, LV_JRVAL, LV_JRCNT.
        PERFORM GET_JR_AVG USING IT_MIC1-INSLOT IT_MIC1-MIC
                        CHANGING LV_ISJR LV_JRVAL LV_JRCNT.
        IF LV_ISJR = 'X'.
          CLEAR: IT_MIC1-CMICMIT, IT_MIC1-MICMIT.
          IF LV_JRCNT > 0.
            PERFORM MICFMT USING IT_MIC1-MIC IT_LOT-WERKS
                    CHANGING GV_DEC GV_UOM.
            WRITE LV_JRVAL TO IT_MIC1-CMICMIT
                  EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
            IT_MIC1-MICMIT = LV_JRVAL.
          ELSE.
            IT_MIC1-CMICMIT = '-'.
            IT_MIC1-MICMIT = 0.
          ENDIF.
        ELSE.
        SELECT SINGLE CODE1 VORGLFNR INTO (IT_MIC1-CMICMIT, IT_MIC1-VORGLFNR)
          FROM QAMR
          WHERE QAMR~PRUEFLOS = IT_MIC1-INSLOT
          AND QAMR~MERKNR = IT_MIC1-MERKNR.

        IF IT_MIC1-CMICMIT IS INITIAL.
          " Ambil nilai single result (cycle) terakhir dari QASE untuk MVTR/OTR
          IF IT_MIC1-MIC CS 'MVTR' OR IT_MIC1-MIC CS 'OTR'.
            DATA: BEGIN OF LT_QASE OCCURS 0,
                    PROBENR LIKE QASE-PROBENR,
                    ORIGINAL_INPUT LIKE QASE-ORIGINAL_INPUT,
                    MESSWERT LIKE QASE-MESSWERT,
                  END OF LT_QASE.
            CLEAR LT_QASE. REFRESH LT_QASE.
            SELECT PROBENR ORIGINAL_INPUT MESSWERT INTO TABLE LT_QASE
              FROM QASE
              WHERE PRUEFLOS = IT_MIC1-INSLOT
                AND MERKNR = IT_MIC1-MERKNR
                AND ATTRIBUT = ''.
            SORT LT_QASE BY PROBENR DESCENDING.
            READ TABLE LT_QASE INDEX 1.
            IF SY-SUBRC = 0.
              IF LT_QASE-ORIGINAL_INPUT IS NOT INITIAL.
                IT_MIC1-CMICMIT = LT_QASE-ORIGINAL_INPUT.
                IT_MIC1-MICMIT  = LT_QASE-MESSWERT.
              ELSE.
                PERFORM MICFMT USING IT_MIC1-MIC IT_LOT-WERKS
                        CHANGING GV_DEC GV_UOM.
                WRITE LT_QASE-MESSWERT TO IT_MIC1-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
                IT_MIC1-MICMIT  = LT_QASE-MESSWERT.
              ENDIF.
              IT_MIC1-PROBENR = LT_QASE-PROBENR.
              IT_MIC1-MESSWERT = LT_QASE-MESSWERT.
            ENDIF.
          ENDIF.

          " Fallback ke rata-rata (MITTELWERT) jika bukan MVTR/OTR atau nilai kosong
          IF IT_MIC1-CMICMIT IS INITIAL.
            DATA: LV_MITTEL TYPE QAMR-MITTELWERT.
            CLEAR LV_MITTEL.
            SELECT SINGLE MITTELWERT VORGLFNR
              INTO (LV_MITTEL, IT_MIC1-VORGLFNR)
              FROM QAMR
              WHERE QAMR~PRUEFLOS = IT_MIC1-INSLOT
              AND QAMR~MERKNR = IT_MIC1-MERKNR.
            IF LV_MITTEL IS NOT INITIAL.
              PERFORM MICFMT USING IT_MIC1-MIC IT_LOT-WERKS
                      CHANGING GV_DEC GV_UOM.
              WRITE LV_MITTEL TO IT_MIC1-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
              IT_MIC1-MICMIT = LV_MITTEL.
            ENDIF.
          ENDIF.

          IF IT_MIC1-CMICMIT IS INITIAL.
            DATA: LV_ANZWERTG TYPE QAMR-ANZWERTG.
            CLEAR LV_ANZWERTG.
            SELECT SINGLE MITTELWERT ANZWERTG INTO (IT_MIC1-MICMIT, LV_ANZWERTG)
              FROM QAMR
              WHERE QAMR~PRUEFLOS = IT_MIC1-INSLOT
              AND QAMR~MERKNR = IT_MIC1-MERKNR.

            IF SY-SUBRC = 0 AND LV_ANZWERTG > 0.
              PERFORM MICFMT USING IT_MIC1-MIC IT_LOT-WERKS
                      CHANGING GV_DEC GV_UOM.
              WRITE IT_MIC1-MICMIT TO IT_MIC1-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
            ELSE.
              IT_MIC1-CMICMIT = '-'.
              IT_MIC1-MICMIT = 0.
            ENDIF.
          ENDIF.
        ENDIF.
        ENDIF.
      CLEAR IT_MIC1-METHOD.
      IF LV_KUNNR IS NOT INITIAL.
        SELECT SINGLE METHOD
          INTO IT_MIC1-METHOD
          FROM ZMAP_COA
          WHERE MATNR = IT_LOT-MATNR
            AND MIC   = IT_MIC1-MIC
            AND KUNNR = LV_KUNNR
            AND DELETION NE 'X'.
      ENDIF.
      IF IT_MIC1-METHOD IS INITIAL.
        SELECT SINGLE METHOD
          INTO IT_MIC1-METHOD
          FROM ZMAP_COA
          WHERE MATNR = IT_LOT-MATNR
            AND MIC   = IT_MIC1-MIC
            AND KUNNR = ' '
            AND DELETION NE 'X'.
      ENDIF.
      PERFORM MICFMT USING IT_MIC1-MIC IT_LOT-WERKS
              CHANGING GV_DEC GV_UOM.
      IT_MIC1-UOM = GV_UOM.
          MOVE-CORRESPONDING IT_MIC1 TO WA_DATA.
          APPEND WA_DATA TO IT_DATA.
        ENDLOOP.
    ELSE.
      APPEND IT_LOT TO IT_DATA.
    ENDIF.
  ENDLOOP.

  IT_LOOP[] = IT_DATA[].
  DELETE ADJACENT DUPLICATES FROM IT_LOOP COMPARING CHARG.
  LOOP AT IT_LOOP.
    IT_LOOP-CMICMIT = ''.
    MODIFY IT_LOOP.
  ENDLOOP.

  DELETE IT_DATA WHERE MIC IS INITIAL.

  " Enhancement: Aggregate/Average MIC results for identical Material
  DATA: IT_DATA_AVG LIKE IT_DATA OCCURS 0 WITH HEADER LINE,
        LV_SUM TYPE QAMR-MITTELWERT,
        LV_COUNT TYPE I,
        LV_LAST_INSLOT TYPE QALS-PRUEFLOS. " Untuk tracking unique INSLOT MVTR/OTR

  " Sort ditambahkan INSLOT agar bisa mendeteksi perubahan INSLOT
  SORT IT_DATA BY VBELN MATNR MIC INSLOT.
  LOOP AT IT_DATA.
    IF IT_DATA_AVG IS INITIAL.
      IT_DATA_AVG = IT_DATA.
      IF IT_DATA-CMICMIT = '-'.
        LV_SUM = 0.
        LV_COUNT = 0.
      ELSE.
        LV_SUM = IT_DATA-MICMIT.
        LV_COUNT = 1.
        LV_LAST_INSLOT = IT_DATA-INSLOT.
      ENDIF.
    ELSEIF IT_DATA_AVG-VBELN = IT_DATA-VBELN AND
           IT_DATA_AVG-MATNR = IT_DATA-MATNR AND
           IT_DATA_AVG-MIC   = IT_DATA-MIC.
           
      IF IT_DATA-CMICMIT <> '-'.
        DATA: LV_PROCESS TYPE C VALUE 'X'.
        " Khusus untuk MVTR dan OTR, kita hanya ambil average dari unique JR (INSLOT)
        IF IT_DATA-MIC CS 'MVTR' OR IT_DATA-MIC CS 'OTR'.
          IF IT_DATA-INSLOT = LV_LAST_INSLOT.
            LV_PROCESS = ' '. " Skip, karena INSLOT ini sudah dihitung last cyclenya
          ELSE.
            LV_LAST_INSLOT = IT_DATA-INSLOT.
          ENDIF.
        ENDIF.

        IF LV_PROCESS = 'X'.
          LV_SUM = LV_SUM + IT_DATA-MICMIT.
          LV_COUNT = LV_COUNT + 1.
          IF IT_DATA_AVG-CMICMIT = '-'.
            IT_DATA_AVG-CMICMIT = IT_DATA-CMICMIT.
          ENDIF.
        ENDIF.
      ENDIF.
    ELSE.
      IF LV_COUNT > 0.
        IT_DATA_AVG-MICMIT = LV_SUM / LV_COUNT.
        " Jika data bersifat kuantitatif (ada sum), ubah format text CMICMIT ke hasil rata-rata
        IF LV_COUNT > 1 AND LV_SUM <> 0.
          PERFORM MICFMT USING IT_DATA_AVG-MIC IT_DATA_AVG-WERKS
                  CHANGING GV_DEC GV_UOM.
          WRITE IT_DATA_AVG-MICMIT TO IT_DATA_AVG-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
        ENDIF.
      ELSE.
        IT_DATA_AVG-CMICMIT = '-'.
        IT_DATA_AVG-MICMIT = 0.
      ENDIF.
      APPEND IT_DATA_AVG.

      IT_DATA_AVG = IT_DATA.
      IF IT_DATA-CMICMIT = '-'.
        LV_SUM = 0.
        LV_COUNT = 0.
      ELSE.
        LV_SUM = IT_DATA-MICMIT.
        LV_COUNT = 1.
        LV_LAST_INSLOT = IT_DATA-INSLOT.
      ENDIF.
    ENDIF.
  ENDLOOP.
  IF IT_DATA_AVG IS NOT INITIAL.
    IF LV_COUNT > 0.
      IT_DATA_AVG-MICMIT = LV_SUM / LV_COUNT.
      IF LV_COUNT > 1 AND LV_SUM <> 0.
        PERFORM MICFMT USING IT_DATA_AVG-MIC IT_DATA_AVG-WERKS
                CHANGING GV_DEC GV_UOM.
        WRITE IT_DATA_AVG-MICMIT TO IT_DATA_AVG-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
      ENDIF.
    ELSE.
      IT_DATA_AVG-CMICMIT = '-'.
      IT_DATA_AVG-MICMIT = 0.
    ENDIF.
    APPEND IT_DATA_AVG.
  ENDIF.

  IT_DATA[] = IT_DATA_AVG[].

  LOOP AT IT_DATA.
    IT_DATA-CHK = ''.
    IT_DATA-NUMMIC = 2.
    READ TABLE IT_ZMAP WITH KEY MIC = IT_DATA-MIC BINARY SEARCH.
    IF SY-SUBRC EQ 0.
      IT_DATA-CHK = 'X'.
      IT_DATA-NUMMIC = 1.
      IT_DATA-NUM = IT_ZMAP-NUM.
    ENDIF.

    " Backup original aggregated QM value
    IT_DATA-ORIG_CMICMIT = IT_DATA-CMICMIT.

    " --- BEGIN ZLOG_COA CHECK ---
    DATA: WA_ZLOG TYPE ZLOG_COA,
          LV_KUNNR_LOG TYPE KUNNR.

    CLEAR LV_KUNNR_LOG.
    SELECT SINGLE KUNAG INTO LV_KUNNR_LOG FROM LIKP WHERE VBELN = IT_DATA-VBELN.

    CLEAR WA_ZLOG.
    SELECT SINGLE VALUE1 VALUE2 INTO (WA_ZLOG-VALUE1, WA_ZLOG-VALUE2) FROM ZLOG_COA
      WHERE PRUEFLOS = IT_DATA-INSLOT
        AND MIC = IT_DATA-MIC
        AND KUNNR = LV_KUNNR_LOG
        AND DELETION <> 'X'.

    IF SY-SUBRC = 0.
      " If there is data in ZLOG_COA, override CMICMIT (Preview)
      IF WA_ZLOG-VALUE2 IS NOT INITIAL.
        IT_DATA-CMICMIT = WA_ZLOG-VALUE2.
      ELSEIF WA_ZLOG-VALUE1 IS NOT INITIAL.
        PERFORM MICFMT USING IT_DATA-MIC IT_DATA-WERKS
                CHANGING GV_DEC GV_UOM.
        WRITE WA_ZLOG-VALUE1 TO IT_DATA-CMICMIT EXPONENT 0 DECIMALS GV_DEC LEFT-JUSTIFIED.
        IT_DATA-MICMIT = WA_ZLOG-VALUE1.
      ENDIF.
    ENDIF.
    " --- END ZLOG_COA CHECK ---

    " Menyimpan status tersimpan saat ini untuk keperluan validasi sebelum EXEC
    IT_DATA-SAVED_CMICMIT = IT_DATA-CMICMIT.

    MODIFY IT_DATA.
  ENDLOOP.
  SORT IT_DATA BY VBELN CHK DESCENDING.
ENDFORM.                    "get_data
*&---------------------------------------------------------------------*
*&      Form  GET_MIC
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM GET_MIC .
  DATA : INS  LIKE QALS-PRUEFLOS,
         CTR TYPE I.

  CLEAR IT_MIC. REFRESH IT_MIC.
  CLEAR IT_MIC2. REFRESH IT_MIC2.

  LOOP AT IT_ZMAP.
    CLEAR INS.
    " Tentukan sumber Inspection Lot berdasarkan MAPPING
    IF IT_ZMAP-MAPPING CS 'SR Base Film'.
      INS = LOT_SR_BASE.
    ELSEIF IT_ZMAP-MAPPING CS 'JR Base Film'.
      INS = LOT_JR_BASE.
    ELSEIF IT_ZMAP-MAPPING CS 'SR Converting'.
      INS = LOT_SR_CONV.
    ELSEIF IT_ZMAP-MAPPING CS 'JR Converting'.
      INS = LOT_JR_CONV.
    ELSE.
      " Default fallback jika kosong, mungkin ambil dari SR Convert/Base
      INS = LOT_SR_CONV.
    ENDIF.

    IF INS IS NOT INITIAL.
      SELECT SINGLE VERWMERKM KURZTEXT TOLERANZUN TOLERANZOB MERKNR STELLEN
        INTO (IT_MIC-MIC,IT_MIC-MICDES,IT_MIC-MICMIN,IT_MIC-MICMAX,IT_MIC-MERKNR,IT_MIC-STELLEN)
        FROM QAMV
        WHERE PRUEFLOS = INS
          AND VERWMERKM = IT_ZMAP-MIC.

      IF SY-SUBRC EQ 0.
        PERFORM COPY.
        IT_MIC-SEQ = 1.
        IT_MIC-INSLOT = INS.
        APPEND IT_MIC TO IT_MIC2.
      ELSE.
        " Pengecualian untuk MVTR/OTR Barrier yang MIC-nya bisa berbeda (seperti WVTR/O2TR)
        IF IT_ZMAP-MIC CS 'MVTR' OR IT_ZMAP-MIC CS 'OTR'.
          SELECT VERWMERKM KURZTEXT TOLERANZUN TOLERANZOB MERKNR STELLEN
            INTO (IT_MIC-MIC,IT_MIC-MICDES,IT_MIC-MICMIN,IT_MIC-MICMAX,IT_MIC-MERKNR,IT_MIC-STELLEN)
            FROM QAMV
            WHERE PRUEFLOS = INS.
            IF IT_MIC-MIC CS 'MVTR' OR IT_MIC-MIC CS 'WVTR' OR
               IT_MIC-MIC CS 'OTR'  OR IT_MIC-MIC CS 'O2TR'.
               IF IT_MIC-MIC CS IT_ZMAP-MIC OR IT_ZMAP-MIC CS IT_MIC-MIC OR
                  ( IT_ZMAP-MIC CS 'MVTR' AND IT_MIC-MIC CS 'WVTR' ) OR
                  ( IT_ZMAP-MIC CS 'OTR' AND IT_MIC-MIC CS 'O2TR' ).
                 PERFORM COPY.
                 IT_MIC-SEQ = 5.
                 IT_MIC-INSLOT = INS.
                 IF IT_MIC-MIC CS 'MVTR' OR
                    IT_MIC-MIC CS 'WVTR'.
                   IT_MIC-BARRIER_TYPE = 'MVTR'.
                 ELSEIF IT_MIC-MIC CS 'OTR' OR
                        IT_MIC-MIC CS 'O2TR'.
                   IT_MIC-BARRIER_TYPE = 'OTR'.
                 ELSE.
                   IT_MIC-BARRIER_TYPE = 'X'.
                 ENDIF.
                 IT_MIC-MIC = IT_ZMAP-MIC. " Timpa agar sesuai dengan Mapping
                 APPEND IT_MIC TO IT_MIC2.
               ENDIF.
            ENDIF.
          ENDSELECT.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDLOOP.

  " Pastikan semua MIC dari ZMAP_COA tetap masuk ke list meskipun tidak ada di Inspection Lot
  SORT IT_MIC2 BY MIC.
  LOOP AT IT_ZMAP.
    READ TABLE IT_MIC2 WITH KEY MIC = IT_ZMAP-MIC BINARY SEARCH.
    IF SY-SUBRC <> 0.
      CLEAR IT_MIC.
      PERFORM COPY. " Fix: isi VBELN/POSNR/CHARG/MATNR dst agar match balik di GET_DATA
      IT_MIC-MIC = IT_ZMAP-MIC.
      IT_MIC-METHOD = IT_ZMAP-METHOD.
      SELECT SINGLE KURZTEXT INTO IT_MIC-MICDES FROM QPMT WHERE MKMNR = IT_ZMAP-MIC AND SPRACHE = 'E'.
      IF SY-SUBRC <> 0.
        IT_MIC-MICDES = IT_ZMAP-MIC.
      ENDIF.
      SELECT SINGLE MASSEINHSW INTO IT_MIC-UOM FROM QPMK WHERE MKMNR = IT_ZMAP-MIC.
      IT_MIC-SEQ = 99. " Penanda tidak ada di Inspection Lot
      IT_MIC-INSLOT = ''.
      APPEND IT_MIC TO IT_MIC2.
    ENDIF.
  ENDLOOP.

  SORT IT_MIC2 BY MIC ASCENDING.
  DELETE ADJACENT DUPLICATES FROM IT_MIC2 COMPARING MIC.

  CLEAR CTR.
  CTR = LINES( IT_MIC2 ).
  IF CTR NE 0.
    APPEND LINES OF IT_MIC2 FROM 1 TO CTR TO IT_MIC1.
  ENDIF.
  CLEAR IT_MIC2. REFRESH IT_MIC2.
ENDFORM.                    " GET_MIC
*&---------------------------------------------------------------------*
*&      Form  COPY
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM COPY .
  IT_MIC-VBELN = IT_DATA-VBELN.
  IT_MIC-POSNR = IT_DATA-POSNR.
  IT_MIC-CHARG = IT_DATA-CHARG.
  IT_MIC-NOMSR = IT_DATA-NOMSR.
  IT_MIC-ZZTYPE = IT_DATA-ZZTYPE.
  IT_MIC-MATNR = IT_DATA-MATNR.
  IT_MIC-UECHA = IT_DATA-UECHA.
  IT_MIC-WERKS = IT_DATA-WERKS.
ENDFORM.                    " COPY
*&---------------------------------------------------------------------*
*&      Form  DOWNLOAD
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM DOWNLOAD .
  TABLES RLGRAP.

  DATA:  DEF_PATH LIKE RLGRAP-FILENAME.
  DATA: TMP_FILENAME LIKE RLGRAP-FILENAME.
  DATA V_FILENAME TYPE STRING.
  DATA : BEGIN OF IT_FIELDNAMES OCCURS 0,
           FIELD(30),
         END OF IT_FIELDNAMES.

  REFRESH IT_FIELDNAMES.
  CLEAR IT_FIELDNAMES.
  IT_FIELDNAMES-FIELD = 'Nomor ODO'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Item'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Batch'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Nomor SR'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Material'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'MIC'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'MIC Description'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Unit Of Measure'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Testing Method '.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Lower Limit'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Upper Limit'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Value'.
  APPEND IT_FIELDNAMES.

  CLEAR: IT_EXPORT.
  REFRESH:IT_EXPORT.
  LOOP AT IT_DATA WHERE CHK EQ 'X'.
    CLEAR IT_EXPORT.
    IT_EXPORT-VBELN = IT_DATA-VBELN.
    IT_EXPORT-UECHA = IT_DATA-UECHA.
    IT_EXPORT-CHARG = IT_DATA-CHARG.
    IT_EXPORT-NOMSR = IT_DATA-NOMSR.
    IT_EXPORT-MATNR = IT_DATA-MATNR.
    IT_EXPORT-MIC = IT_DATA-MIC.
    IT_EXPORT-MICDES = IT_DATA-MICDES.
    IT_EXPORT-UOM = IT_DATA-UOM.
    IT_EXPORT-METHOD = IT_DATA-METHOD.
    IT_EXPORT-MICMIN = IT_DATA-MICMIN.
    IT_EXPORT-MICMAX = IT_DATA-MICMAX.
    IT_EXPORT-CMICMIT = IT_DATA-CMICMIT.
*    IT_EXPORT-CHK = IT_DATA-CHK.
    APPEND IT_EXPORT.
  ENDLOOP.

  CALL FUNCTION 'WS_FILENAME_GET'
    EXPORTING
      DEF_FILENAME     = RLGRAP-FILENAME
      DEF_PATH         = DEF_PATH
      MASK             = ',*.xls.'
      MODE             = 'S'
      TITLE            = TEXT-011
    IMPORTING
      FILENAME         = TMP_FILENAME
    EXCEPTIONS
      INV_WINSYS       = 01
      NO_BATCH         = 02
      SELECTION_CANCEL = 03
      SELECTION_ERROR  = 04.

  IF SY-SUBRC = 0.
    RLGRAP-FILENAME = TMP_FILENAME.
  ELSE.
    EXIT.
  ENDIF.
  CONCATENATE RLGRAP-FILENAME '.XLS' INTO V_FILENAME.
*  V_FILENAME = RLGRAP-FILENAME.
  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      FILENAME              = V_FILENAME
      FILETYPE              = 'ASC'
      WRITE_FIELD_SEPARATOR = 'X'
      CONFIRM_OVERWRITE     = 'X'
      SHOW_TRANSFER_STATUS  = 'X'
    TABLES
      DATA_TAB              = IT_EXPORT
      FIELDNAMES            = IT_FIELDNAMES.

  IF SY-SUBRC <> 0.
    MESSAGE I000(0K) WITH 'Download error'.
    STOP.
  ENDIF.

ENDFORM.                    " DOWNLOAD
*&---------------------------------------------------------------------*
*&      Form  SELALL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM SELALL .
  LOOP AT IT_DATA WHERE CHK NE 'X'.
    IT_DATA-CHK = 'X'.
    MODIFY IT_DATA.
  ENDLOOP.
ENDFORM.                    " SELALL
*&---------------------------------------------------------------------*
*&      Form  DESALL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM DESALL .
  LOOP AT IT_DATA WHERE CHK EQ 'X'.
    IT_DATA-CHK = ''.
    MODIFY IT_DATA.
  ENDLOOP.
ENDFORM.                    " DESALL
*&---------------------------------------------------------------------*
*&      Form  DOWNLOAD_DETAIL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM DOWNLOAD_DETAIL .
*  TABLES RLGRAP.

  DATA:  DEF_PATH LIKE RLGRAP-FILENAME.
  DATA: TMP_FILENAME LIKE RLGRAP-FILENAME.
  DATA V_FILENAME TYPE STRING.
  DATA : BEGIN OF IT_FIELDNAMES OCCURS 0,
           FIELD(30),
         END OF IT_FIELDNAMES.

  REFRESH IT_FIELDNAMES.
  CLEAR IT_FIELDNAMES.
  IT_FIELDNAMES-FIELD = 'Properties'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Unit of Measure'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Testing Method'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Lower Limit'.
  APPEND IT_FIELDNAMES.

  IT_FIELDNAMES-FIELD = 'Upper Limit'.
  APPEND IT_FIELDNAMES.
  IT_FIELDNAMES-FIELD = 'Value'.
  APPEND IT_FIELDNAMES.
  REFRESH IT_DETAILD.
  LOOP AT IT_DETAIL WHERE CHK = 'X'.
    MOVE-CORRESPONDING IT_DETAIL TO IT_DETAILD.
    APPEND IT_DETAILD.
  ENDLOOP.

  CALL FUNCTION 'WS_FILENAME_GET'
    EXPORTING
      DEF_FILENAME     = RLGRAP-FILENAME
      DEF_PATH         = DEF_PATH
      MASK             = ',*.xls.'
      MODE             = 'S'
      TITLE            = TEXT-011
    IMPORTING
      FILENAME         = TMP_FILENAME
    EXCEPTIONS
      INV_WINSYS       = 01
      NO_BATCH         = 02
      SELECTION_CANCEL = 03
      SELECTION_ERROR  = 04.

  IF SY-SUBRC = 0.
    RLGRAP-FILENAME = TMP_FILENAME.
  ELSE.
    EXIT.
  ENDIF.
  CONCATENATE RLGRAP-FILENAME '.XLS' INTO V_FILENAME.
  CALL FUNCTION 'GUI_DOWNLOAD'
    EXPORTING
      FILENAME              = V_FILENAME
      FILETYPE              = 'ASC'
      WRITE_FIELD_SEPARATOR = 'X'
      CONFIRM_OVERWRITE     = 'X'
      SHOW_TRANSFER_STATUS  = 'X'
    TABLES
      DATA_TAB              = IT_DETAILD
      FIELDNAMES            = IT_FIELDNAMES.

  IF SY-SUBRC <> 0.
    MESSAGE I000(0K) WITH 'Download error'.
    STOP.
  ENDIF.

ENDFORM.                    " DOWNLOAD_DETAIL
*&---------------------------------------------------------------------*
*&      Form  SELMAPPING
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM SELMAPPING .
  LOOP AT IT_DATA.
    IT_DATA-CHK = ''.
    READ TABLE IT_ZMAP WITH KEY MIC = IT_DATA-MIC BINARY SEARCH.
    IF SY-SUBRC EQ 0.
      IT_DATA-CHK = 'X'.
    ENDIF.
    MODIFY IT_DATA.
  ENDLOOP.
  SORT IT_DATA BY VBELN CHK DESCENDING.
ENDFORM.                    " SELMAPPING
*&---------------------------------------------------------------------*
*&      Form  F_PRINT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM F_PRINT .
  DATA: I_NAST LIKE NAST.
  DATA: I_SSFCOMPOP TYPE SSFCOMPOP.
  DATA: I_SSFCTRLOP  TYPE SSFCTRLOP.
  DATA: I_RECIPIENT          TYPE SWOTOBJID.
  DATA: I_SENDER             TYPE SWOTOBJID.
  DATA: I_ADDR_KEY           LIKE ADDR_KEY.

  DATA: IT_QAMV TYPE QAMV OCCURS 0 WITH HEADER LINE.
  DATA: QUANTITY TYPE CHAR12.

  PERFORM GET_COMPANY_NAME. "ADD NEW COMPANY 19/09/2018

  WRITE NTGEW TO QUANTITY DECIMALS 2.
  LOOP AT IT_DETAIL WHERE CHK EQ 'X'.
*    it_QAMV-VERWMERKM = it_detail-MIC.
    IT_QAMV-KURZTEXT = IT_DETAIL-MICDES.
    IT_QAMV-STEUERKZ = IT_DETAIL-UOM.
    IT_QAMV-DUMMY40 = IT_DETAIL-METHOD.
    IT_QAMV-TOLERANZOB = IT_DETAIL-MICMIN.
    IT_QAMV-TOLERANZUN = IT_DETAIL-MICMAX.
    IT_QAMV-DUMMY20 = IT_DETAIL-CMICMIT.
*    it_QAMV-PHYSPROBE = it_detail-NUM.
*    it_QAMV-LTEXTKZ = it_detail-NUMMIC.
*    it_QAMV-LTEXTSPR = it_detail-CHK.
*    it_QAMV-LTEXTEKZ = it_detail-TYPE.
    APPEND IT_QAMV.
  ENDLOOP.


  CALL FUNCTION 'SSF_FUNCTION_MODULE_NAME'
    EXPORTING
      FORMNAME           = 'ZQMF_COA'
    IMPORTING
      FM_NAME            = LF_FM_NAME
    EXCEPTIONS
      NO_FORM            = 1
      NO_FUNCTION_MODULE = 2
      OTHERS             = 3.
  CALL FUNCTION LF_FM_NAME
    EXPORTING
      CONTROL_PARAMETERS = I_SSFCTRLOP
      OUTPUT_OPTIONS     = I_SSFCOMPOP
      CUSTOMER           = NAME1
      DELIVERY           = VBELN
      PRODUCT            = PRODUCT
      QUANTITY           = QUANTITY
      WIDTH              = WIDTH
      COMPANYTXT         = COMPANYTXT
    TABLES
      IT_QAMV            = IT_QAMV
    EXCEPTIONS
      FORMATTING_ERROR   = 1
      INTERNAL_ERROR     = 2
      SEND_ERROR         = 3
      USER_CANCELED      = 4
      OTHERS             = 5.

*PROPERTIS = IT_DETAIL-MICDES
*UNIT OF MEASURE = IT_DETAIL-UOM
*METHOD = IT_DETAIL-METHOD
*LOWER LIMIT = IT_DETAIL-MICMIN
*UPPER LIMIT = IT_DETAIL-MICMAX
*VALUE = IT_DETAIL-CMICMIT
ENDFORM.                    " F_PRINT

*&---------------------------------------------------------------------*
*&      Form  GET_COMPANY_NAME
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM GET_COMPANY_NAME. "ADD NEW COMPANY 19/09/2018

  DATA:ZWERKS LIKE LIPS-WERKS,
       ZVBELN LIKE LIPS-VBELN.

  IF VBELN IS NOT INITIAL.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        INPUT  = VBELN
      IMPORTING
        OUTPUT = ZVBELN.
    SELECT SINGLE WERKS FROM LIPS INTO ZWERKS WHERE VBELN EQ ZVBELN.
  ELSE.
    MESSAGE 'Nomor ODO tidak ada!' TYPE 'I'.
    STOP.
  ENDIF.

  SELECT SINGLE T001~BUTXT FROM T001
    JOIN T001K ON T001~BUKRS EQ T001K~BUKRS INTO COMPANYTXT
    WHERE T001K~BWKEY EQ ZWERKS.

ENDFORM.                    "GET_COMPANY_NAME
*&---------------------------------------------------------------------*
*&      Form  GET_TRACED_LOTS
*&---------------------------------------------------------------------*
TYPES: BEGIN OF TY_TRACE_DATA,
         MOTHER_ROLL         TYPE C LENGTH 50,
         LOT_JR_CONV         TYPE QALS-PRUEFLOS,
         LOT_SR_BASE         TYPE QALS-PRUEFLOS,
         LOT_JR_BASE         TYPE QALS-PRUEFLOS,
         L_JR_CONV_BATCH     TYPE MCH1-CHARG,
         L_SR_BASE_BATCH     TYPE MCH1-CHARG,
         L_JR_BASE_BATCH     TYPE MCH1-CHARG,
         LOT_SR_CONV_SIBLING TYPE QALS-PRUEFLOS,
       END OF TY_TRACE_DATA.
DATA: GT_TRACE_DATA TYPE TABLE OF TY_TRACE_DATA,
      GS_TRACE_DATA TYPE TY_TRACE_DATA.

FORM GET_TRACED_LOTS.
  DATA: L_AUFNR LIKE AFPO-AUFNR,
        L_MBLNR LIKE MSEG-MBLNR,
        L_MATNR LIKE MSEG-MATNR,
        L_CHARG LIKE MSEG-CHARG,
        L_LICHA LIKE MCH1-LICHA,
        L_LEN TYPE I,
        L_TEMP TYPE I.
  DATA: L_JR_CONV_BATCH LIKE MCH1-CHARG,
        L_SR_BASE_BATCH LIKE MCH1-CHARG,
        L_JR_BASE_BATCH LIKE MCH1-CHARG,
        LT_SR TYPE TABLE OF ZQM_GET_BATCH_SR WITH HEADER LINE.

  DATA: V_LINE  TYPE C LENGTH 20,
        V_CODE  TYPE C LENGTH 20,
        V_MOYE  TYPE C LENGTH 20,
        V_SEQ   TYPE C LENGTH 20,
        V_DUMMY TYPE C LENGTH 50,
        L_MOTHER_ROLL TYPE C LENGTH 50.

  DATA: LV_SEARCH_SR TYPE CHARG_D,
        LV_LATEST_SR TYPE CHARG_D.

  DATA: LV_FALLBACK_AUFNR_1 LIKE MSEG-AUFNR,
        LV_FALLBACK_PARENT_1 LIKE MSEG-CHARG,
        LV_FALLBACK_AUFNR_2 LIKE MSEG-AUFNR,
        LV_FALLBACK_PARENT_2 LIKE MSEG-CHARG.

  CLEAR: LOT_SR_CONV, LOT_JR_CONV, LOT_SR_BASE, LOT_JR_BASE,
         L_JR_CONV_BATCH, L_SR_BASE_BATCH, L_JR_BASE_BATCH,
         GS_TRACE_DATA.

  " Edited by J. Budi (Antigravity) on 29.06.2026 - Inspection Lot Tracing via Sibling SR
  SPLIT IT_DATA-NOMSR AT SPACE INTO V_LINE V_CODE V_MOYE V_SEQ V_DUMMY.
  CONCATENATE V_LINE V_CODE V_MOYE V_SEQ INTO L_MOTHER_ROLL SEPARATED BY SPACE.

  " 1. SR Converting Lot
  SELECT SINGLE PRUEFLOS INTO LOT_SR_CONV FROM QALS WHERE CHARG = IT_DATA-CHARG AND ART = 'Z04'.

  READ TABLE GT_TRACE_DATA INTO GS_TRACE_DATA WITH KEY MOTHER_ROLL = L_MOTHER_ROLL BINARY SEARCH.
  IF SY-SUBRC = 0.
    L_JR_CONV_BATCH = GS_TRACE_DATA-L_JR_CONV_BATCH.
    LOT_JR_CONV     = GS_TRACE_DATA-LOT_JR_CONV.
    L_SR_BASE_BATCH = GS_TRACE_DATA-L_SR_BASE_BATCH.
    LOT_SR_BASE     = GS_TRACE_DATA-LOT_SR_BASE.
    L_JR_BASE_BATCH = GS_TRACE_DATA-L_JR_BASE_BATCH.
    LOT_JR_BASE     = GS_TRACE_DATA-LOT_JR_BASE.
    IF LOT_SR_CONV IS INITIAL.
      LOT_SR_CONV = GS_TRACE_DATA-LOT_SR_CONV_SIBLING.
    ENDIF.
    RETURN.
  ENDIF.

  IF LOT_SR_CONV IS INITIAL.
    PERFORM GET_ORIGINAL_BATCH USING IT_DATA-CHARG CHANGING LV_SEARCH_SR.
    CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
      EXPORTING
        CHARG_S = LV_SEARCH_SR
      IMPORTING
        CHARG_J = L_JR_CONV_BATCH.
    " --- BEGIN FALLBACK WRAPPER ---
    " Jika JR gagal ditemukan, mungkin terputus oleh Change Grade (309) di tengah hierarki
    IF L_JR_CONV_BATCH IS INITIAL.

      PERFORM GET_VALID_ORDER_FROM_MSEG USING LV_SEARCH_SR CHANGING LV_FALLBACK_AUFNR_1.
      IF LV_FALLBACK_AUFNR_1 IS NOT INITIAL.
        PERFORM GET_VALID_COMPONENT_FROM_MSEG USING LV_FALLBACK_AUFNR_1 CHANGING LV_FALLBACK_PARENT_1.
        IF LV_FALLBACK_PARENT_1 IS NOT INITIAL.
          " Bypass change grade parent
          PERFORM GET_ORIGINAL_BATCH USING LV_FALLBACK_PARENT_1 CHANGING LV_SEARCH_SR.
          " Coba panggil lagi
          CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
            EXPORTING
              CHARG_S = LV_SEARCH_SR
            IMPORTING
              CHARG_J = L_JR_CONV_BATCH.
        ENDIF.
      ENDIF.
    ENDIF.
    " --- END FALLBACK WRAPPER ---

    IF L_JR_CONV_BATCH IS NOT INITIAL.
      REFRESH LT_SR.
      CALL FUNCTION 'ZQM_GET_BATCH_SR_BY_JR'
        EXPORTING
          CHARGJR = L_JR_CONV_BATCH
        TABLES
          T_SR    = LT_SR.

      LOOP AT LT_SR.
        PERFORM GET_NEWEST_BATCH USING LT_SR-CHARG CHANGING LV_LATEST_SR.
        SELECT SINGLE PRUEFLOS INTO GS_TRACE_DATA-LOT_SR_CONV_SIBLING FROM QALS WHERE CHARG = LV_LATEST_SR AND ART = 'Z04'.
        IF GS_TRACE_DATA-LOT_SR_CONV_SIBLING IS NOT INITIAL.
          LOT_SR_CONV = GS_TRACE_DATA-LOT_SR_CONV_SIBLING.
          EXIT. " Ditemukan inspection lot dari salah satu saudara SR
        ENDIF.
      ENDLOOP.
    ENDIF.
  ELSE.
    " Jika LOT_SR_CONV langsung ketemu, kita tetap butuh JR_CONV_BATCH untuk mencari LOT_JR_CONV dan SR_BASE_BATCH
    PERFORM GET_ORIGINAL_BATCH USING IT_DATA-CHARG CHANGING LV_SEARCH_SR.
    CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
      EXPORTING
        CHARG_S = LV_SEARCH_SR
      IMPORTING
        CHARG_J = L_JR_CONV_BATCH.
    " --- BEGIN FALLBACK WRAPPER ---
    " Jika JR gagal ditemukan, mungkin terputus oleh Change Grade (309) di tengah hierarki
    IF L_JR_CONV_BATCH IS INITIAL.

      PERFORM GET_VALID_ORDER_FROM_MSEG USING LV_SEARCH_SR CHANGING LV_FALLBACK_AUFNR_1.
      IF LV_FALLBACK_AUFNR_1 IS NOT INITIAL.
        PERFORM GET_VALID_COMPONENT_FROM_MSEG USING LV_FALLBACK_AUFNR_1 CHANGING LV_FALLBACK_PARENT_1.
        IF LV_FALLBACK_PARENT_1 IS NOT INITIAL.
          " Bypass change grade parent
          PERFORM GET_ORIGINAL_BATCH USING LV_FALLBACK_PARENT_1 CHANGING LV_SEARCH_SR.
          " Coba panggil lagi
          CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
            EXPORTING
              CHARG_S = LV_SEARCH_SR
            IMPORTING
              CHARG_J = L_JR_CONV_BATCH.
        ENDIF.
      ENDIF.
    ENDIF.
    " --- END FALLBACK WRAPPER ---
  ENDIF.

  " 2. JR Converting Lot
  IF L_JR_CONV_BATCH IS NOT INITIAL.
    SELECT SINGLE PRUEFLOS INTO LOT_JR_CONV FROM QALS WHERE CHARG = L_JR_CONV_BATCH AND ( ART = 'Z02' OR ART = 'Z03' ).
    IF LOT_JR_CONV IS INITIAL.
      PERFORM GET_JR_SIBLING_LOT USING L_JR_CONV_BATCH CHANGING LOT_JR_CONV.
    ENDIF.
  ENDIF.

  " 3. Cari SR Base Film Batch
  IF L_JR_CONV_BATCH IS NOT INITIAL.
    PERFORM GET_VALID_ORDER_FROM_MSEG USING L_JR_CONV_BATCH CHANGING L_AUFNR.

    IF L_AUFNR IS NOT INITIAL.
      PERFORM GET_VALID_COMPONENT_FROM_MSEG USING L_AUFNR CHANGING L_CHARG.
      IF L_CHARG IS NOT INITIAL.
        SELECT SINGLE MATNR INTO L_MATNR FROM MCH1 WHERE CHARG = L_CHARG.
      ENDIF.

      IF L_CHARG IS NOT INITIAL.
        L_LEN = STRLEN( L_MATNR ).
        L_TEMP = L_LEN - 1.
        IF L_MATNR(2) = 'SR' AND ( L_MATNR+L_TEMP(1) = 'A' OR L_MATNR+L_TEMP(1) = 'O' ).
          SELECT SINGLE LICHA INTO L_LICHA FROM MCH1 WHERE MATNR = L_MATNR AND CHARG = L_CHARG.
          IF L_LICHA IS NOT INITIAL.
            L_SR_BASE_BATCH = L_LICHA.
          ELSE.
            L_SR_BASE_BATCH = L_CHARG.
          ENDIF.
        ELSE.
          L_SR_BASE_BATCH = L_CHARG.
        ENDIF.
      ENDIF.
    ENDIF.
  ELSE.
    " Jika tidak ada JR Conv, mungkin inputnya langsung SR Base?
    L_SR_BASE_BATCH = IT_DATA-CHARG.
  ENDIF.

  " Fix dinamis (permintaan user 15/07/2026): JR yang ditemukan di atas (L_JR_CONV_BATCH)
  " ternyata tidak punya turunan SR Base Film (tidak dikonsumsi order manapun sebagai
  " komponen SR/JR). Artinya JR tsb sebenarnya JR Base Film (terminal, bukan JR Converting),
  " dan batch DO ini sendiri sudah SR Base Film - bukan SR Converting. Re-label supaya
  " tracing lanjut dengan benar ke JR Base Film, bukan berhenti/salah label.
  IF L_JR_CONV_BATCH IS NOT INITIAL AND L_SR_BASE_BATCH IS INITIAL.
    L_JR_BASE_BATCH = L_JR_CONV_BATCH.
    LOT_JR_BASE = LOT_JR_CONV.
    L_SR_BASE_BATCH = IT_DATA-CHARG.
    LOT_SR_BASE = LOT_SR_CONV.
    CLEAR: L_JR_CONV_BATCH, LOT_JR_CONV, LOT_SR_CONV.
  ENDIF.

  " 3. SR Base Film Lot
  IF L_SR_BASE_BATCH IS NOT INITIAL AND LOT_SR_BASE IS INITIAL.
    SELECT SINGLE PRUEFLOS INTO LOT_SR_BASE FROM QALS WHERE CHARG = L_SR_BASE_BATCH AND ART = 'Z04'.

    IF L_JR_BASE_BATCH IS INITIAL. " Skip re-search kalau JR Base sudah ketemu dari re-labeling di atas
    IF LOT_SR_BASE IS INITIAL.
      PERFORM GET_ORIGINAL_BATCH USING L_SR_BASE_BATCH CHANGING LV_SEARCH_SR.
      CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
        EXPORTING
          CHARG_S = LV_SEARCH_SR
        IMPORTING
          CHARG_J = L_JR_BASE_BATCH.
    " --- BEGIN FALLBACK WRAPPER ---
    " Jika JR gagal ditemukan, mungkin terputus oleh Change Grade (309) di tengah hierarki
    IF L_JR_BASE_BATCH IS INITIAL.

      PERFORM GET_VALID_ORDER_FROM_MSEG USING LV_SEARCH_SR CHANGING LV_FALLBACK_AUFNR_2.
      IF LV_FALLBACK_AUFNR_2 IS NOT INITIAL.
        PERFORM GET_VALID_COMPONENT_FROM_MSEG USING LV_FALLBACK_AUFNR_2 CHANGING LV_FALLBACK_PARENT_2.
        IF LV_FALLBACK_PARENT_2 IS NOT INITIAL.
          " Bypass change grade parent
          PERFORM GET_ORIGINAL_BATCH USING LV_FALLBACK_PARENT_2 CHANGING LV_SEARCH_SR.
          " Coba panggil lagi
          CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
            EXPORTING
              CHARG_S = LV_SEARCH_SR
            IMPORTING
              CHARG_J = L_JR_BASE_BATCH.
        ENDIF.
      ENDIF.
    ENDIF.
    " --- END FALLBACK WRAPPER ---

      IF L_JR_BASE_BATCH IS NOT INITIAL.
        REFRESH LT_SR.
        CALL FUNCTION 'ZQM_GET_BATCH_SR_BY_JR'
          EXPORTING
            CHARGJR = L_JR_BASE_BATCH
          TABLES
            T_SR    = LT_SR.

        LOOP AT LT_SR.
          PERFORM GET_NEWEST_BATCH USING LT_SR-CHARG CHANGING LV_LATEST_SR.
          SELECT SINGLE PRUEFLOS INTO LOT_SR_BASE FROM QALS WHERE CHARG = LV_LATEST_SR AND ART = 'Z04'.
          IF LOT_SR_BASE IS NOT INITIAL.
            EXIT.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ELSE.
      " Cari JR_BASE_BATCH untuk mencari LOT_JR_BASE
      PERFORM GET_ORIGINAL_BATCH USING L_SR_BASE_BATCH CHANGING LV_SEARCH_SR.
      CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
        EXPORTING
          CHARG_S = LV_SEARCH_SR
        IMPORTING
          CHARG_J = L_JR_BASE_BATCH.
    " --- BEGIN FALLBACK WRAPPER ---
    " Jika JR gagal ditemukan, mungkin terputus oleh Change Grade (309) di tengah hierarki
    IF L_JR_BASE_BATCH IS INITIAL.

      PERFORM GET_VALID_ORDER_FROM_MSEG USING LV_SEARCH_SR CHANGING LV_FALLBACK_AUFNR_2.
      IF LV_FALLBACK_AUFNR_2 IS NOT INITIAL.
        PERFORM GET_VALID_COMPONENT_FROM_MSEG USING LV_FALLBACK_AUFNR_2 CHANGING LV_FALLBACK_PARENT_2.
        IF LV_FALLBACK_PARENT_2 IS NOT INITIAL.
          " Bypass change grade parent
          PERFORM GET_ORIGINAL_BATCH USING LV_FALLBACK_PARENT_2 CHANGING LV_SEARCH_SR.
          " Coba panggil lagi
          CALL FUNCTION 'ZQM_GET_BATCH_JR_BY_SR'
            EXPORTING
              CHARG_S = LV_SEARCH_SR
            IMPORTING
              CHARG_J = L_JR_BASE_BATCH.
        ENDIF.
      ENDIF.
    ENDIF.
    " --- END FALLBACK WRAPPER ---
    ENDIF.
    ENDIF. " penutup guard L_JR_BASE_BATCH IS INITIAL
  ENDIF.

  " 4. JR Base Film Lot
  IF L_JR_BASE_BATCH IS NOT INITIAL AND LOT_JR_BASE IS INITIAL.
    SELECT SINGLE PRUEFLOS INTO LOT_JR_BASE FROM QALS WHERE CHARG = L_JR_BASE_BATCH AND ( ART = 'Z02' OR ART = 'Z03' ).
    IF LOT_JR_BASE IS INITIAL.
      PERFORM GET_JR_SIBLING_LOT USING L_JR_BASE_BATCH CHANGING LOT_JR_BASE.
    ENDIF.
  ENDIF.

  " Setelah selesai mencari semuanya, simpan ke cache
  GS_TRACE_DATA-MOTHER_ROLL = L_MOTHER_ROLL.
  GS_TRACE_DATA-L_JR_CONV_BATCH = L_JR_CONV_BATCH.
  GS_TRACE_DATA-LOT_JR_CONV = LOT_JR_CONV.
  GS_TRACE_DATA-L_SR_BASE_BATCH = L_SR_BASE_BATCH.
  GS_TRACE_DATA-LOT_SR_BASE = LOT_SR_BASE.
  GS_TRACE_DATA-L_JR_BASE_BATCH = L_JR_BASE_BATCH.
  GS_TRACE_DATA-LOT_JR_BASE = LOT_JR_BASE.
  IF GS_TRACE_DATA-LOT_SR_CONV_SIBLING IS INITIAL AND LOT_SR_CONV IS NOT INITIAL.
    GS_TRACE_DATA-LOT_SR_CONV_SIBLING = LOT_SR_CONV.
  ENDIF.
  APPEND GS_TRACE_DATA TO GT_TRACE_DATA.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_ORIGINAL_BATCH
*&---------------------------------------------------------------------*
FORM GET_ORIGINAL_BATCH USING P_BATCH CHANGING P_ORIGINAL_BATCH.
  DATA: LV_OLD_BATCH TYPE CHARG_D.
  P_ORIGINAL_BATCH = P_BATCH.
  DO.
    CLEAR LV_OLD_BATCH.
    SELECT CHARG INTO LV_OLD_BATCH FROM ZBATCHISTORY
      UP TO 1 ROWS
      WHERE NCHARG = P_ORIGINAL_BATCH
      ORDER BY BUDAT DESCENDING UZEIT DESCENDING.
    ENDSELECT.
    IF SY-SUBRC = 0 AND LV_OLD_BATCH IS NOT INITIAL.
      P_ORIGINAL_BATCH = LV_OLD_BATCH.
    ELSE.
      EXIT.
    ENDIF.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_NEWEST_BATCH
*&---------------------------------------------------------------------*
FORM GET_NEWEST_BATCH USING P_BATCH CHANGING P_NEWEST_BATCH.
  DATA: LV_NEW_BATCH TYPE CHARG_D.
  P_NEWEST_BATCH = P_BATCH.
  DO.
    CLEAR LV_NEW_BATCH.
    SELECT NCHARG INTO LV_NEW_BATCH FROM ZBATCHISTORY
      UP TO 1 ROWS
      WHERE CHARG = P_NEWEST_BATCH
      ORDER BY BUDAT DESCENDING UZEIT DESCENDING.
    ENDSELECT.
    IF SY-SUBRC = 0 AND LV_NEW_BATCH IS NOT INITIAL.
      P_NEWEST_BATCH = LV_NEW_BATCH.
    ELSE.
      EXIT.
    ENDIF.
  ENDDO.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_JR_SIBLING_LOT
*&---------------------------------------------------------------------*
FORM GET_JR_SIBLING_LOT USING P_BATCH TYPE CHARG_D
                        CHANGING P_LOT TYPE QALS-PRUEFLOS.
  DATA: LV_CUOBJ_BM TYPE MCH1-CUOBJ_BM,
        LV_OBJEK TYPE AUSP-OBJEK,
        LV_ROLL_STR TYPE AUSP-ATWRT.

  DATA: BEGIN OF LT_PARTS OCCURS 0,
          PART(50) TYPE C,
        END OF LT_PARTS.
  DATA: LV_PART(50) TYPE C,
        LV_PREFIX(50) TYPE C,
        LV_SEQ_STR(10) TYPE C,
        LV_SEQ_NUM TYPE I,
        LV_LINES TYPE I.

  DATA: LV_IDX TYPE I,
        LV_START TYPE I,
        LV_END TYPE I,
        LV_SEQ_NEW_STR TYPE C LENGTH 3,
        LV_BATCH_NEW TYPE CHARG_D,
        LV_ROLL_NEW TYPE AUSP-ATWRT.

  DATA: BEGIN OF LT_SIBLING_ROLLS OCCURS 0,
          ATWRT TYPE AUSP-ATWRT,
        END OF LT_SIBLING_ROLLS.

  DATA: BEGIN OF LT_CUOBJ OCCURS 0,
          OBJEK TYPE AUSP-OBJEK,
        END OF LT_CUOBJ.

  DATA: BEGIN OF LT_CUOBJ_BM OCCURS 0,
          CUOBJ_BM TYPE MCH1-CUOBJ_BM,
        END OF LT_CUOBJ_BM.

  DATA: BEGIN OF LT_BATCHES OCCURS 0,
          CHARG TYPE MCH1-CHARG,
        END OF LT_BATCHES.

  DATA: BEGIN OF LT_LOTS OCCURS 0,
          PRUEFLOS TYPE QALS-PRUEFLOS,
          CHARG TYPE QALS-CHARG,
        END OF LT_LOTS.

  CLEAR P_LOT.
  IF P_BATCH IS INITIAL.
    RETURN.
  ENDIF.



  " 2. Dapatkan CUOBJ_BM (Internal Object Number) dari tabel MCH1 untuk P_BATCH
  SELECT SINGLE CUOBJ_BM INTO LV_CUOBJ_BM
    FROM MCH1
    WHERE CHARG = P_BATCH.

  IF SY-SUBRC <> 0 OR LV_CUOBJ_BM IS INITIAL.
    RETURN.
  ENDIF.

  LV_OBJEK = LV_CUOBJ_BM.

  " 3. Dapatkan teks Nomor Roll dari AUSP
  SELECT SINGLE ATWRT INTO LV_ROLL_STR
    FROM AUSP
    WHERE OBJEK = LV_OBJEK
      AND ATINN = ATINN_ROLL
      AND KLART = '023'
      AND MAFID = 'O'.

  IF SY-SUBRC <> 0 OR LV_ROLL_STR IS INITIAL.
    RETURN.
  ENDIF.

  " 4. Ekstrak prefix dan sequence dari Nomor Roll (misal: "W CGA 108 001")
  SPLIT LV_ROLL_STR AT SPACE INTO TABLE LT_PARTS.
  DESCRIBE TABLE LT_PARTS LINES LV_LINES.

  IF LV_LINES >= 2.
    READ TABLE LT_PARTS INDEX LV_LINES.
    LV_SEQ_STR = LT_PARTS-PART.

    " Reconstruct prefix
    DATA: LV_IDX_PREFIX TYPE I.
    LV_IDX_PREFIX = 1.
    CLEAR LV_PREFIX.
    WHILE LV_IDX_PREFIX < LV_LINES.
      READ TABLE LT_PARTS INDEX LV_IDX_PREFIX.
      LV_PART = LT_PARTS-PART.
      IF LV_PREFIX IS INITIAL.
        LV_PREFIX = LV_PART.
      ELSE.
        CONCATENATE LV_PREFIX LV_PART INTO LV_PREFIX SEPARATED BY SPACE.
      ENDIF.
      LV_IDX_PREFIX = LV_IDX_PREFIX + 1.
    ENDWHILE.

    " Pastikan karakter terakhir (sequence) adalah angka
    IF LV_SEQ_STR CO '0123456789 '.
      LV_SEQ_NUM = LV_SEQ_STR.

      LV_START = LV_SEQ_NUM - 10.
      LV_END = LV_SEQ_NUM + 10.
      IF LV_START < 1.
        LV_START = 1.
      ENDIF.

      " Generate Sibling Rolls
      LV_IDX = LV_START.
      WHILE LV_IDX <= LV_END.
        IF LV_IDX <> LV_SEQ_NUM.
          UNPACK LV_IDX TO LV_SEQ_NEW_STR. " Akan menghasilkan padding '001' dst
          CONCATENATE LV_PREFIX LV_SEQ_NEW_STR INTO LV_ROLL_NEW SEPARATED BY SPACE.
          LT_SIBLING_ROLLS-ATWRT = LV_ROLL_NEW.
          APPEND LT_SIBLING_ROLLS.
        ENDIF.
        LV_IDX = LV_IDX + 1.
      ENDWHILE.

      IF LT_SIBLING_ROLLS[] IS NOT INITIAL.
        " 5. Konversi balik Nomor Roll Sibling ke Batch Sibling (CUOBJ)
        SELECT OBJEK INTO TABLE LT_CUOBJ
          FROM AUSP
          FOR ALL ENTRIES IN LT_SIBLING_ROLLS
          WHERE ATINN = ATINN_ROLL
            AND ATWRT = LT_SIBLING_ROLLS-ATWRT
            AND KLART = '023'
            AND MAFID = 'O'.

        IF LT_CUOBJ[] IS NOT INITIAL.
          " Pindahkan OBJEK (CHAR 50) ke CUOBJ_BM (NUMC 18) agar kompatibel dengan FOR ALL ENTRIES
          LOOP AT LT_CUOBJ.
            LT_CUOBJ_BM-CUOBJ_BM = LT_CUOBJ-OBJEK.
            APPEND LT_CUOBJ_BM.
          ENDLOOP.

          " 6. Dapatkan CHARG dari MCH1
          IF LT_CUOBJ_BM[] IS NOT INITIAL.
            SELECT CHARG INTO TABLE LT_BATCHES
              FROM MCH1
              FOR ALL ENTRIES IN LT_CUOBJ_BM
              WHERE CUOBJ_BM = LT_CUOBJ_BM-CUOBJ_BM.
          ENDIF.

          IF LT_BATCHES[] IS NOT INITIAL.
            " 7. Cari Lot Inspeksi (QALS)
            SELECT PRUEFLOS CHARG INTO TABLE LT_LOTS
              FROM QALS
              FOR ALL ENTRIES IN LT_BATCHES
              WHERE CHARG = LT_BATCHES-CHARG
                AND ( ART = 'Z02' OR ART = 'Z03' ).

            IF SY-SUBRC = 0.
              SORT LT_LOTS BY PRUEFLOS DESCENDING.
              READ TABLE LT_LOTS INDEX 1.
              IF SY-SUBRC = 0.
                P_LOT = LT_LOTS-PRUEFLOS.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_VALID_ORDER_FROM_MSEG
*&---------------------------------------------------------------------*
* BKTXT dokumen GR (101) yang sedang di-trace. Di-set oleh GET_VALID_ORDER_FROM_MSEG,
* dibaca GET_VALID_COMPONENT_FROM_MSEG. BKTXT = identitas transaksi / nomor roll, dan
* merupakan penghubung yang benar antara posting 101 dan 261 dalam SATU production order.
DATA: GV_TRACE_BKTXT TYPE MKPF-BKTXT.

FORM GET_VALID_ORDER_FROM_MSEG USING P_CHARG CHANGING P_AUFNR.
  DATA: LT_MSEG TYPE TABLE OF MSEG WITH HEADER LINE,
        LT_CANC TYPE TABLE OF MSEG WITH HEADER LINE.
  DATA: LV_COMBINE LIKE AFPO-AUFNR.
  CLEAR P_AUFNR.
  SELECT AUFNR MBLNR MJAHR ZEILE SMBLN SJAHR SMBLP BWART CHARG
    INTO CORRESPONDING FIELDS OF TABLE LT_MSEG
    FROM MSEG
    WHERE CHARG = P_CHARG AND BWART IN ('101', '102')
    %_HINTS ORACLE 'INDEX("MSEG" "MSEG~Z07")'.

  IF SY-SUBRC = 0.
    LT_CANC[] = LT_MSEG[].
    DELETE LT_CANC WHERE SMBLN IS INITIAL.
    LOOP AT LT_CANC.
      DELETE LT_MSEG WHERE MBLNR = LT_CANC-SMBLN AND MJAHR = LT_CANC-SJAHR AND ZEILE = LT_CANC-SMBLP.
    ENDLOOP.
    DELETE LT_MSEG WHERE SMBLN IS NOT INITIAL OR BWART = '102'.

    SORT LT_MSEG BY MBLNR DESCENDING ZEILE DESCENDING.
    READ TABLE LT_MSEG INDEX 1.
    IF SY-SUBRC = 0.
      P_AUFNR = LT_MSEG-AUFNR.

      " Fix A (user 18/07/2026): ambil BKTXT dokumen GR (101) ini, dipakai
      " GET_VALID_COMPONENT_FROM_MSEG untuk memilih komponen 261 pasangan roll ini.
      " Bukti: order 100000072887 punya 8 posting 261 / 4 batch berbeda, dibedakan
      " HANYA oleh BKTXT. Logic lama ambil MBLNR terbesar - salah roll tanpa gejala.
      SELECT SINGLE BKTXT INTO GV_TRACE_BKTXT
        FROM MKPF
        WHERE MBLNR = LT_MSEG-MBLNR
          AND MJAHR = LT_MSEG-MJAHR.

      " Fix B (user 18/07/2026): resolve COLLECTIVE ORDER. AUFNR dari MSEG 101 bisa
      " order referensi (mis. A29000002540) yang TIDAK punya komponen 261 sama sekali;
      " order asli dicari via AFPO-MILL_OC_AUFNR_U. Tanpa ini tracing MATI di hop
      " pertama sehingga MIC level Base Film (mis. PALZTH00) selalu kosong.
      CLEAR LV_COMBINE.
      SELECT SINGLE AUFNR INTO LV_COMBINE
        FROM AFPO
        WHERE MILL_OC_AUFNR_U = P_AUFNR.
      IF SY-SUBRC = 0 AND LV_COMBINE IS NOT INITIAL.
        P_AUFNR = LV_COMBINE.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.

*&---------------------------------------------------------------------*
*&      Form  GET_VALID_COMPONENT_FROM_MSEG
*&---------------------------------------------------------------------*
FORM GET_VALID_COMPONENT_FROM_MSEG USING P_AUFNR CHANGING P_CHARG.
  DATA: BEGIN OF LT_MKPF OCCURS 0,
          MBLNR LIKE MKPF-MBLNR,
          MJAHR LIKE MKPF-MJAHR,
          BKTXT LIKE MKPF-BKTXT,
        END OF LT_MKPF.
  DATA: LT_MSEG TYPE TABLE OF MSEG WITH HEADER LINE,
        LT_CANC TYPE TABLE OF MSEG WITH HEADER LINE.
  CLEAR P_CHARG.
  SELECT AUFNR MBLNR MJAHR ZEILE SMBLN SJAHR SMBLP BWART CHARG MATNR
    INTO CORRESPONDING FIELDS OF TABLE LT_MSEG
    FROM MSEG
    WHERE AUFNR = P_AUFNR AND BWART IN ('261', '262', '901', '902') AND CHARG <> ''.

  IF SY-SUBRC = 0.
    LT_CANC[] = LT_MSEG[].
    DELETE LT_CANC WHERE SMBLN IS INITIAL.
    LOOP AT LT_CANC.
      DELETE LT_MSEG WHERE MBLNR = LT_CANC-SMBLN AND MJAHR = LT_CANC-SJAHR AND ZEILE = LT_CANC-SMBLP.
    ENDLOOP.
    DELETE LT_MSEG WHERE SMBLN IS NOT INITIAL OR BWART = '262' OR BWART = '902'.

    " Fix BKTXT (user 18/07/2026): buang komponen yang BUKAN milik transaksi/roll yang
    " sama dengan dokumen 101-nya. Satu order bisa punya banyak roll, dan BKTXT adalah
    " satu-satunya pembeda. Kalau BKTXT 101 kosong (data lama), filter dilewati.
    IF GV_TRACE_BKTXT IS NOT INITIAL AND LT_MSEG[] IS NOT INITIAL.
      CLEAR LT_MKPF. REFRESH LT_MKPF.
      SELECT MBLNR MJAHR BKTXT INTO TABLE LT_MKPF
        FROM MKPF
        FOR ALL ENTRIES IN LT_MSEG
        WHERE MBLNR = LT_MSEG-MBLNR
          AND MJAHR = LT_MSEG-MJAHR.
      SORT LT_MKPF BY MBLNR MJAHR.
      LOOP AT LT_MSEG.
        CLEAR LT_MKPF.
        READ TABLE LT_MKPF WITH KEY MBLNR = LT_MSEG-MBLNR
                                    MJAHR = LT_MSEG-MJAHR BINARY SEARCH.
        IF SY-SUBRC <> 0 OR LT_MKPF-BKTXT <> GV_TRACE_BKTXT.
          DELETE LT_MSEG.
        ENDIF.
      ENDLOOP.
    ENDIF.

    SORT LT_MSEG BY MBLNR DESCENDING ZEILE DESCENDING.
    LOOP AT LT_MSEG.
      " Pastikan yang diambil adalah material Base Film (SR/JR), bukan komponen pelengkap
      IF LT_MSEG-MATNR(2) = 'SR' OR LT_MSEG-MATNR(2) = 'JR'.
        P_CHARG = LT_MSEG-CHARG.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDIF.
ENDFORM.


*&--------------------------------------------------------------------*
*&      Form  MICFMT
*&--------------------------------------------------------------------*
* Fix (user 18/07/2026): sebelumnya semua WRITE meng-hardcode DECIMALS 3,
* sehingga value tidak mengikuti master MIC (mis. SEWESTMZ STELLEN=0
* seharusnya tampil 55, bukan 54.842). Form ini mengambil STELLEN + unit
* dari QPMK per MIC dan per plant, hasilnya di-cache di GT_MICFMT.
*&--------------------------------------------------------------------*
*&      Form  GET_JR_AVG
*&--------------------------------------------------------------------*
* Enhancement (user 18/07/2026): untuk MIC ber-mapping JR (Converting /
* Base Film), nilai = RATA-RATA across semua sibling roll JR dalam 1
* mother roll (mis. E EWE 076 001..004), bukan hanya 1 roll yang di-slit
* ke SR-nya. Sebab QC merekam inspeksi JR sekali per order/jumbo di satu
* roll perwakilan; roll lain lot-nya kosong. Hanya lot dengan ANZWERTG>0
* yang ikut rata-rata (skip kosong). P_ISJR='X' bila INSLOT adalah lot JR
* (QALS ART Z02/Z03); bila bukan, caller pakai logika lama (SR tak berubah).
FORM GET_JR_AVG USING P_INSLOT P_MIC
                CHANGING P_ISJR
                         P_VAL TYPE QAMR-MITTELWERT
                         P_CNT TYPE I.
  DATA: L_CHARG TYPE QALS-CHARG, L_ART TYPE QALS-ART.
  DATA: L_CUOBJ TYPE MCH1-CUOBJ_BM, L_OBJEK TYPE AUSP-OBJEK.
  DATA: L_ROLL TYPE AUSP-ATWRT.
  DATA: L_SUM TYPE QAMR-MITTELWERT, L_MW TYPE QAMR-MITTELWERT.
  DATA: L_AZ TYPE QAMR-ANZWERTG, L_MK TYPE QAMV-MERKNR.
  DATA: BEGIN OF LT_PARTS OCCURS 0, PART(50) TYPE C, END OF LT_PARTS.
  DATA: L_PART(50), L_PREFIX(50), L_SEQ(10), L_SEQN TYPE I.
  DATA: L_LINES TYPE I, L_IDX TYPE I, L_IDXP TYPE I.
  DATA: L_START TYPE I, L_END TYPE I.
  DATA: L_SEQNEW TYPE C LENGTH 3, L_ROLLNEW TYPE AUSP-ATWRT.
  DATA: BEGIN OF LT_SIB OCCURS 0, ATWRT TYPE AUSP-ATWRT, END OF LT_SIB.
  DATA: BEGIN OF LT_OBJ OCCURS 0, OBJEK TYPE AUSP-OBJEK, END OF LT_OBJ.
  DATA: BEGIN OF LT_CUB OCCURS 0, CUOBJ_BM TYPE MCH1-CUOBJ_BM,
        END OF LT_CUB.
  DATA: BEGIN OF LT_BAT OCCURS 0, CHARG TYPE MCH1-CHARG, END OF LT_BAT.
  DATA: BEGIN OF LT_LOT OCCURS 0, PRUEFLOS TYPE QALS-PRUEFLOS,
        END OF LT_LOT.

  CLEAR: P_ISJR, P_VAL, P_CNT, L_SUM.

  SORT GT_JRAVG BY INSLOT MIC.
  READ TABLE GT_JRAVG INTO GS_JRAVG
    WITH KEY INSLOT = P_INSLOT MIC = P_MIC BINARY SEARCH.
  IF SY-SUBRC = 0.
    P_ISJR = GS_JRAVG-ISJR. P_VAL = GS_JRAVG-VAL. P_CNT = GS_JRAVG-CNT.
    RETURN.
  ENDIF.

  IF P_INSLOT IS NOT INITIAL.
    SELECT SINGLE CHARG ART INTO (L_CHARG, L_ART) FROM QALS
      WHERE PRUEFLOS = P_INSLOT.
    IF SY-SUBRC = 0 AND ( L_ART = 'Z02' OR L_ART = 'Z03' ).
      P_ISJR = 'X'.
      SELECT SINGLE CUOBJ_BM INTO L_CUOBJ FROM MCH1
        WHERE CHARG = L_CHARG.
      L_OBJEK = L_CUOBJ.
      CLEAR L_ROLL.
      IF L_CUOBJ IS NOT INITIAL.
        SELECT SINGLE ATWRT INTO L_ROLL FROM AUSP
          WHERE OBJEK = L_OBJEK AND ATINN = ATINN_ROLL
            AND KLART = '023' AND MAFID = 'O'.
      ENDIF.
      IF L_ROLL IS NOT INITIAL.
        SPLIT L_ROLL AT SPACE INTO TABLE LT_PARTS.
        DESCRIBE TABLE LT_PARTS LINES L_LINES.
        IF L_LINES >= 2.
          CLEAR LT_PARTS.
          READ TABLE LT_PARTS INDEX L_LINES.
          L_SEQ = LT_PARTS-PART.
          L_IDXP = 1. CLEAR L_PREFIX.
          WHILE L_IDXP < L_LINES.
            CLEAR LT_PARTS.
            READ TABLE LT_PARTS INDEX L_IDXP.
            L_PART = LT_PARTS-PART.
            IF L_PREFIX IS INITIAL.
              L_PREFIX = L_PART.
            ELSE.
              CONCATENATE L_PREFIX L_PART INTO L_PREFIX
                SEPARATED BY SPACE.
            ENDIF.
            L_IDXP = L_IDXP + 1.
          ENDWHILE.
          IF L_SEQ CO '0123456789 '.
            L_SEQN = L_SEQ.
            L_START = L_SEQN - 10. L_END = L_SEQN + 10.
            IF L_START < 1. L_START = 1. ENDIF.
            L_IDX = L_START.
            WHILE L_IDX <= L_END.
              UNPACK L_IDX TO L_SEQNEW.
              CONCATENATE L_PREFIX L_SEQNEW INTO L_ROLLNEW
                SEPARATED BY SPACE.
              LT_SIB-ATWRT = L_ROLLNEW. APPEND LT_SIB.
              L_IDX = L_IDX + 1.
            ENDWHILE.
          ENDIF.
        ENDIF.
      ENDIF.
      IF LT_SIB[] IS NOT INITIAL.
        SORT LT_SIB BY ATWRT.
        DELETE ADJACENT DUPLICATES FROM LT_SIB COMPARING ATWRT.
        SELECT OBJEK INTO TABLE LT_OBJ FROM AUSP
          FOR ALL ENTRIES IN LT_SIB
          WHERE ATINN = ATINN_ROLL AND ATWRT = LT_SIB-ATWRT
            AND KLART = '023' AND MAFID = 'O'.
        LOOP AT LT_OBJ.
          LT_CUB-CUOBJ_BM = LT_OBJ-OBJEK. APPEND LT_CUB.
        ENDLOOP.
        IF LT_CUB[] IS NOT INITIAL.
          SORT LT_CUB BY CUOBJ_BM.
          DELETE ADJACENT DUPLICATES FROM LT_CUB COMPARING CUOBJ_BM.
          SELECT CHARG INTO TABLE LT_BAT FROM MCH1
            FOR ALL ENTRIES IN LT_CUB
            WHERE CUOBJ_BM = LT_CUB-CUOBJ_BM.
        ENDIF.
        IF LT_BAT[] IS NOT INITIAL.
          SORT LT_BAT BY CHARG.
          DELETE ADJACENT DUPLICATES FROM LT_BAT COMPARING CHARG.
          SELECT PRUEFLOS INTO TABLE LT_LOT FROM QALS
            FOR ALL ENTRIES IN LT_BAT
            WHERE CHARG = LT_BAT-CHARG
              AND ( ART = 'Z02' OR ART = 'Z03' ).
          SORT LT_LOT BY PRUEFLOS.
          DELETE ADJACENT DUPLICATES FROM LT_LOT COMPARING PRUEFLOS.
        ENDIF.
        LOOP AT LT_LOT.
          CLEAR L_MK.
          SELECT SINGLE MERKNR INTO L_MK FROM QAMV
            WHERE PRUEFLOS = LT_LOT-PRUEFLOS
              AND VERWMERKM = P_MIC.
          IF SY-SUBRC = 0 AND L_MK IS NOT INITIAL.
            CLEAR: L_MW, L_AZ.
            SELECT SINGLE MITTELWERT ANZWERTG INTO (L_MW, L_AZ)
              FROM QAMR
              WHERE PRUEFLOS = LT_LOT-PRUEFLOS AND MERKNR = L_MK.
            IF SY-SUBRC = 0 AND L_AZ > 0.
              L_SUM = L_SUM + L_MW. P_CNT = P_CNT + 1.
            ENDIF.
          ENDIF.
        ENDLOOP.
        IF P_CNT > 0.
          P_VAL = L_SUM / P_CNT.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.

  CLEAR GS_JRAVG.
  GS_JRAVG-INSLOT = P_INSLOT. GS_JRAVG-MIC = P_MIC.
  GS_JRAVG-ISJR = P_ISJR. GS_JRAVG-VAL = P_VAL. GS_JRAVG-CNT = P_CNT.
  APPEND GS_JRAVG TO GT_JRAVG.
ENDFORM.

FORM MICFMT USING P_MIC P_WRK
         CHANGING P_DEC TYPE I
                  P_UOM.
  CLEAR: P_DEC, P_UOM.
  IF P_MIC IS INITIAL.
    RETURN.
  ENDIF.
  READ TABLE GT_MICFMT INTO GS_MICFMT
    WITH KEY MKMNR = P_MIC WERKS = P_WRK.
  IF SY-SUBRC <> 0.
    CLEAR GS_MICFMT.
    GS_MICFMT-MKMNR = P_MIC.
    GS_MICFMT-WERKS = P_WRK.
    SELECT SINGLE STELLEN MASSEINHSW
      INTO (GS_MICFMT-STELLEN, GS_MICFMT-UOM)
      FROM QPMK
      WHERE MKMNR = P_MIC
        AND WERKS = P_WRK.
    IF SY-SUBRC <> 0.
      " Master belum ada di plant ini - pakai baris manapun sebagai cadangan
      SELECT SINGLE STELLEN MASSEINHSW
        INTO (GS_MICFMT-STELLEN, GS_MICFMT-UOM)
        FROM QPMK
        WHERE MKMNR = P_MIC.
    ENDIF.
    APPEND GS_MICFMT TO GT_MICFMT.
  ENDIF.
  P_DEC = GS_MICFMT-STELLEN.
  P_UOM = GS_MICFMT-UOM.
ENDFORM.