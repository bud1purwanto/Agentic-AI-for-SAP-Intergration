*&---------------------------------------------------------------------*
*&  Include           ZQMI_UP_CHANGE_GRADE_F01
*&---------------------------------------------------------------------*

AT SELECTION-SCREEN ON VALUE-REQUEST FOR P_LGORT2.
  PERFORM GET_SLOC CHANGING P_LGORT2.

INITIALIZATION.
  MOVE 'Program Information' TO INFO.

AT SELECTION-SCREEN.
  IF SY-UCOMM = 'INFO'.
    PERFORM F_PROG_INFO USING V_PROG.
  ENDIF.

AT SELECTION-SCREEN OUTPUT.
  AUTHORITY-CHECK OBJECT 'Z_OLAP' ID 'ZOLAP' FIELD '1'.
  IF SY-SUBRC NE 0.
    LOOP AT SCREEN.
      IF SCREEN-NAME = 'P1'.
        SCREEN-ACTIVE = '0'.
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ENDIF.

  IF P1 = 'X'.
    LOOP AT SCREEN.
      IF SCREEN-GROUP1 = 'CON'.
        SCREEN-INPUT = 1.
        SCREEN-ACTIVE = 1.
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ELSEIF P2 = 'X'.
    LOOP AT SCREEN.
      IF SCREEN-GROUP1 = 'CON'.
        SCREEN-INPUT = 0.
        SCREEN-ACTIVE = 0.
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ENDIF.

START-OF-SELECTION.
  IF P2 = 'X'.
    IF PIL1 EQ 'X'.
      PERFORM HISTORY.
    ELSEIF PIL2 EQ 'X'.
      PERFORM CEK_OBLI.
      PERFORM GETDATA_CHANGE.
    ENDIF.
  ELSEIF P1 = 'X'.
    IF S_CONN IS INITIAL.
      MESSAGE 'Masukan DBCO Connection name...!' TYPE 'S' DISPLAY LIKE 'E'.
      EXIT.
    ELSE.
      SELECT SINGLE DBMS FROM DBCON INTO DBTYPE WHERE CON_NAME = S_CONN.
      IF SY-SUBRC NE 0.
        MESSAGE 'DBCO Connection not found..!!' TYPE 'I'.
        LEAVE LIST-PROCESSING.
      ENDIF.
    ENDIF.
    PERFORM GETDATA.
    PERFORM SAVE_OLAP.
  ENDIF.


AT USER-COMMAND.
  CASE SY-UCOMM.
    WHEN 'EXIT'.
      FLAG = 'X'.
      LEAVE TO SCREEN 0.
  ENDCASE.
*&---------------------------------------------------------------------*
*&      Form  GETDATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM GETDATA .
  DATA: V_GRAMMAGE LIKE AUSP-ATWRT. " Added by William at 23.05.2022

  SELECT * INTO TABLE IZBATCHISTORY
    FROM ZBATCHISTORY
      WHERE
      ZBATCHISTORY~BUDAT IN P_BUDAT AND
      ZBATCHISTORY~CHARG IN P_CHARG AND
      ZBATCHISTORY~UNAME IN P_UNAME AND
      ZBATCHISTORY~NMEMO IN P_NMEMO AND
      ZBATCHISTORY~WERKS IN P_WERKS AND
      ZBATCHISTORY~LGORT IN P_LGORT.
  LOOP AT IZBATCHISTORY.
    CLEAR TBATCH.
    REFRESH TBATCH.
    CALL FUNCTION 'VB_INIT'
      EXPORTING
        INIT_RESET = 'X'.
    CALL FUNCTION 'VB_BATCH_GET_DETAIL' "
            EXPORTING
              MATNR = IZBATCHISTORY-MATNR
              CHARG = IZBATCHISTORY-CHARG
             WERKS = IZBATCHISTORY-WERKS                    " t001w-werks
             GET_CLASSIFICATION = 'X'       " am07m-xselk
           TABLES
             CHAR_OF_BATCH = TBATCH
           EXCEPTIONS
            NO_MATERIAL              = 1
            NO_BATCH                 = 2
            NO_PLANT                 = 3
            MATERIAL_NOT_FOUND       = 4
            PLANT_NOT_FOUND          = 5
            NO_AUTHORITY             = 6
            BATCH_NOT_EXIST          = 7
            LOCK_ON_BATCH            = 8
            OTHERS                   = 9.

    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCODE'.
    IF SY-SUBRC EQ 0.
      IZBATCHISTORY-TYPE = TBATCH-ATWTB.
    ENDIF.
    " Remarked by William at 23.05.2022
*    READ TABLE TBATCH WITH KEY ATNAM = 'ZZLENGTH'.
*    IF SY-SUBRC EQ 0.
*      IZBATCHISTORY-LENGHT = TBATCH-ATWTB.
*    ENDIF.
    " End remarked by William at 23.05.2022
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZWIDTH'.
    IF SY-SUBRC EQ 0.
      IZBATCHISTORY-WIDTH = TBATCH-ATWTB.
    ENDIF.
    " Remarked and modified by William at 23.05.2022
*    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCONVERSIONROLLKG'.
*    IF SY-SUBRC EQ 0.
**      IZBATCHISTORY-WEIGHT = TBATCH-ATWTB.
*      CONDENSE TBATCH-ATWTB.
*      SPLIT TBATCH-ATWTB AT SPACE INTO IZBATCHISTORY-WEIGHT TEMP.
*    ENDIF.
    IZBATCHISTORY-WEIGHT = IZBATCHISTORY-GPMNG.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZGRAMMAGE'.
    IF SY-SUBRC EQ 0.
      V_GRAMMAGE = TBATCH-ATWTB.
    ENDIF.
    " End remarked and modified by William at 23.05.2022

    " Added by William at 23.05.2022
    PERFORM F_CALCULATE_LENGTH USING IZBATCHISTORY-WEIGHT IZBATCHISTORY-WIDTH V_GRAMMAGE CHANGING IZBATCHISTORY-LENGHT.
*BREAK-POINT.
**    get new batch
*    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG
*      FROM MSEG
*      JOIN AUFK ON AUFK~AUFNR = MSEG~AUFNR
*      WHERE MSEG~CHARG = IZBATCHISTORY-CHARG
*      AND MSEG~BWART IN ('261', '262' )
*      AND AUFK~AUART IN ('ZBS1', 'ZBS2').
*    LOOP AT IT_MSEG WHERE SMBLN IS NOT INITIAL.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-SMBLN.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-MBLNR.
*    ENDLOOP.
*    CLEAR : WA_MSEG.
*    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
*    REFRESH IT_MSEG.
*    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG FROM MSEG
*      WHERE AUFNR = WA_MSEG-AUFNR
*      AND BWART IN ('101', '102' ).
*    LOOP AT IT_MSEG WHERE SMBLN IS NOT INITIAL.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-SMBLN.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-MBLNR.
*    ENDLOOP.
*    CLEAR : IZBATCHISTORY-NCHARG,WA_MSEG.
*    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
*    IZBATCHISTORY-NCHARG = WA_MSEG-CHARG.
*    CLEAR TBATCH.
*    REFRESH TBATCH.
*    CALL FUNCTION 'VB_INIT'
*      EXPORTING
*        INIT_RESET = 'X'.
*    CALL FUNCTION 'VB_BATCH_GET_DETAIL' "
*           EXPORTING
*             MATNR = IZBATCHISTORY-MATNR
*             CHARG = IZBATCHISTORY-NCHARG
*             WERKS = IZBATCHISTORY-WERKS                    " t001w-werks
*             GET_CLASSIFICATION = 'X'       " am07m-xselk
*           TABLES
*             CHAR_OF_BATCH = TBATCH
*           EXCEPTIONS
*            NO_MATERIAL              = 1
*            NO_BATCH                 = 2
*            NO_PLANT                 = 3
*            MATERIAL_NOT_FOUND       = 4
*            PLANT_NOT_FOUND          = 5
*            NO_AUTHORITY             = 6
*            BATCH_NOT_EXIST          = 7
*            LOCK_ON_BATCH            = 8
*            OTHERS                   = 9.
*
*    READ TABLE TBATCH WITH KEY ATNAM = 'ZZLENGTH'.
*    IF SY-SUBRC EQ 0.
*      IZBATCHISTORY-NLENGHT = TBATCH-ATWTB.
*    ENDIF.
*    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCONVERSIONROLLKG'.
*    IF SY-SUBRC EQ 0.
**      IZBATCHISTORY-WEIGHT = TBATCH-ATWTB.
*      CONDENSE TBATCH-ATWTB.
*      SPLIT TBATCH-ATWTB AT SPACE INTO IZBATCHISTORY-NWEIGHT TEMP.
*    ENDIF.

    MODIFY IZBATCHISTORY.
  ENDLOOP.
  PERFORM GET_CRITERIA.
ENDFORM.                    " GETDATA
*&---------------------------------------------------------------------*
*&      Form  GET_CRITERIA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM GET_CRITERIA .
  DATA: V_ATINN LIKE CABN-ATINN.

  DATA:  BEGIN OF IT_GRADE OCCURS 0,
         ATWRT LIKE CAWN-ATWRT,
         ATWTB LIKE CAWNT-ATWTB,
         END OF IT_GRADE.
  DATA: V_SLNID LIKE CUVTAB_VALC-SLNID.
*--- get Criteria Grade baru
  SELECT SINGLE ATINN INTO V_ATINN FROM CABN WHERE ATNAM ='ZZGRADE'.
  SELECT A~ATWRT B~ATWTB INTO TABLE IT_GRADE
  FROM CAWN AS A JOIN CAWNT AS B ON A~ATZHL = B~ATZHL AND A~ATINN = B~ATINN
    WHERE A~ATINN = V_ATINN.

  LOOP AT IZBATCHISTORY.
    READ TABLE IT_GRADE WITH KEY ATWRT = IZBATCHISTORY-GRADE.
    IF SY-SUBRC = 0.
      IZBATCHISTORY-GRDT1 = IT_GRADE-ATWTB.
    ENDIF.

    READ TABLE IT_GRADE WITH KEY ATWRT = IZBATCHISTORY-GRADE2.
    IF SY-SUBRC = 0.
      IZBATCHISTORY-GRDT2 = IT_GRADE-ATWTB.
    ENDIF.
    MODIFY IZBATCHISTORY.
  ENDLOOP.
ENDFORM.                    " GET_CRITERIA
*&---------------------------------------------------------------------*
*&      Form  DISPLAY_DATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM DISPLAY_DATA .
  CLEAR  T_FIELDCAT.
  REFRESH : T_FIELDCAT.
  T_FIELDCAT-TABNAME   = 'IZBATCHISTORY'.
  T_FIELDCAT-FIELDNAME   = 'CHK'.
  T_FIELDCAT-SELTEXT_M   = 'Check'.
  T_FIELDCAT-INPUT     = 'X'.
  T_FIELDCAT-EDIT     = 'X'.
  T_FIELDCAT-CHECKBOX = 'X'.
*  T_FIELDCAT-COL_POS     = 1.
  APPEND T_FIELDCAT.
  CLEAR  T_FIELDCAT.
*  BREAK-POINT.
  PERFORM F_ALV_FIELDCATG_ICON2 USING 'IZBATCHISTORY' :
    'EXIDV'   '' ''  '' ''  'HU'       '' ' ' '' '',
    'BUDAT'   '' ''  '' ''  'Creation Date'       '' ' ' '' '',
    'UZEIT'   '' ''  '' ''  'Creation Time'       '' ' ' '' '',
    'MATNR'   '' ''  '' ''  'Material'    '' ' ' '' '',
    'TYPE'   '' ''  '' ''  'Type/Thickness Film'   '' ' ' '' '',
    'LENGHT'  '' ''  '' ''  'Lenght'      '' ' ' '' '',
    'WEIGHT'  '' ''  '' ''  'Weight'      '' ' ' '' '',
    'WIDTH'  '' ''  '' ''  'Width'      '' ' ' '' '',
    'WERKS'  '' ''  '' ''  'Plant'      '' ' ' '' '',
    'LGORT'  '' ''  '' ''  'Sloc'      '' ' ' '' '',
    'NOROLL'  '' ''  '' ''  'Nomor Roll Asal'      '' ' ' '' '',
    'CHARG'   '' ''  '' ''  'Nomor Batch'   '' ' ' '' '',
    'GRADE'  '' ''  '' ''  'Grade Asal'      '' ' ' '' '',
    'DGRADE'   '' ''  '' ''  'Desc. Grade Asal'   '' ' ' '' '',
    'DCRITA'  '' ''  '' ''  'Criteria Grade Asal'      '' ' ' '' '',
    'NLENGHT'  '' ''  '' ''  'Lenght Baru'      '' ' ' '' '',
    'NWEIGHT'  '' ''  '' ''  'Weight Baru'      '' ' ' '' '',
    'NCHARG'  '' ''  '' ''  'Nomor Batch Baru'      '' ' ' '' '',
    'NOROLL2'  '' ''  '' ''  'Nomor Roll Baru'      '' ' ' '' '',
    'GRADE2'  '' ''  '' ''  'Grade Baru'      '' ' ' '' '',
    'DGRADE2'  '' ''  '' ''  'Desc. Grade baru'      '' ' ' '' '',
    'DCRITB'  '' ''  '' ''  'Criteria Grade Baru'      '' ' ' '' '',
    'NMEMO'  '' ''  '' ''  'Nomor Memo'      '' ' ' '' '',
    'AUTHR'  '' ''  '' ''  'Authorizer'      '' ' ' '' '',
    'NOTES'  '' ''  '' ''  'Terminal'      '' ' ' '' '',
    'UNAME'  '' ''  '' ''  'Username'      '' ' ' '' '',
    'RSLOC'  '' ''  '' ''  'Sloc Raw Recycle'      '' ' ' '' '',
    'SPRNT'  '' ''  '' ''  'Status Print'      '' ' ' '' ''.
*BREAK-POINT.
ENDFORM.                    " DISPLAY_DATA
*&---------------------------------------------------------------------*
*&      Form  F_ALV_FIELDCATG_ICON2
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->FU_TYPES   text
*      -->FU_FNAME   text
*      -->FU_REFTB   text
*      -->FU_REFLD   text
*      -->FU_NOOUT   text
*      -->FU_OUTLN   text
*      -->FU_FLTXT   text
*      -->FU_DOSUM   text
*      -->FU_HOTSP   text
*      -->FU_JUST    text
*      -->FU_ICON    text
*----------------------------------------------------------------------*
FORM F_ALV_FIELDCATG_ICON2 USING FU_TYPES
                                FU_FNAME
                                FU_REFTB
                                FU_REFLD
                                FU_NOOUT
                                FU_OUTLN
                                FU_FLTXT
                                FU_DOSUM
                                FU_HOTSP
                                FU_JUST
                                FU_ICON.


  CLEAR: T_FIELDCAT.
  T_FIELDCAT-TABNAME       = FU_TYPES.
  T_FIELDCAT-FIELDNAME     = FU_FNAME.
  T_FIELDCAT-REF_TABNAME   = FU_REFTB.
  T_FIELDCAT-REF_FIELDNAME = FU_REFLD.
  T_FIELDCAT-NO_OUT        = FU_NOOUT.
  T_FIELDCAT-OUTPUTLEN     = FU_OUTLN.
  T_FIELDCAT-SELTEXT_L     = FU_FLTXT.
*  T_FIELDCAT-REPTEXT_DDIC  = FU_FLTXT.
  T_FIELDCAT-DO_SUM        = FU_DOSUM.
  T_FIELDCAT-HOTSPOT       = FU_HOTSP.
  T_FIELDCAT-JUST          = FU_JUST.
  T_FIELDCAT-ICON          = FU_ICON.
*  T_FIELDCAT-NO_ZERO       = 'X'.
  APPEND T_FIELDCAT.
  CLEAR T_FIELDCAT.

ENDFORM.                    "F_ALV_FIELDCATG_ICON2
*&---------------------------------------------------------------------*
*&      Module  STATUS_0100  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
" STATUS_0100  OUTPUT
*&---------------------------------------------------------------------*
*&      Module  HISTORY  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM HISTORY.
  PERFORM GETDATA.
  IF IZBATCHISTORY[] IS INITIAL.
    MESSAGE 'Tidak ada Data!' TYPE 'I'.
  ELSE.
    SORT IZBATCHISTORY  BY BUDAT DESCENDING UZEIT DESCENDING.
    PERFORM DISPLAY_DATA.
    PERFORM LAYOUT.
    PERFORM DISPLAY.
  ENDIF.
ENDFORM.                 " HISTORY  OUTPUT
*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0100  INPUT
*&---------------------------------------------------------------------*
*       text

*&SPWIZARD: OUTPUT MODULE FOR TC 'TCHANGE'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: UPDATE LINES FOR EQUIVALENT SCROLLBAR
MODULE TCHANGE_CHANGE_TC_ATTR OUTPUT.
  DESCRIBE TABLE IT_CHANGE LINES TCHANGE-LINES.
ENDMODULE.                    "TCHANGE_CHANGE_TC_ATTR OUTPUT

*&SPWIZARD: OUTPUT MODULE FOR TC 'TCHANGE'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: GET LINES OF TABLECONTROL
MODULE TCHANGE_GET_LINES OUTPUT.
  DATA:FLAG2(1) TYPE C,
        MSGEXLENG TYPE STRING.
  FLAG2 = '0'.

  G_TCHANGE_LINES = SY-LOOPC.
  IF IT_CHANGE-CRITB EQ 'S'.
    LOOP AT SCREEN.
      IF SCREEN-NAME = 'IT_CHANGE-RSLOC'.
        SCREEN-INPUT = 1. " klo 0 disable 1 aktif
        MODIFY SCREEN.
      ENDIF.
    ENDLOOP.
  ELSE.
    CLEAR IT_CHANGE-RSLOC.
  ENDIF.

  " EDIT REY
  "1st/2sd -> rw/rs/bf
  IF IT_CHANGE-CRITA EQ '1' OR IT_CHANGE-CRITA EQ '2'.
    IF IT_CHANGE-CRITB EQ 'R' OR IT_CHANGE-CRITB EQ 'B'.
      IF IT_CHANGE-EXLENG EQ '0'.
        LOOP AT SCREEN.
          IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
            SCREEN-INPUT = 1. " klo 0 disable 1 aktif
            MODIFY SCREEN.
          ENDIF.
        ENDLOOP.
      ELSE.
        LOOP AT SCREEN.
          IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
            SCREEN-INPUT = 0. " klo 0 disable 1 aktif
            MODIFY SCREEN.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.
  ENDIF.
  "rw/rs/bf -> 1st/2sd
  IF IT_CHANGE-CRITA EQ 'R' OR IT_CHANGE-CRITA EQ 'B'.
    IF IT_CHANGE-CRITB EQ '1' OR IT_CHANGE-CRITB EQ '2'.

      IF IT_CHANGE-CRITA EQ 'B' OR IT_CHANGE-CRITA EQ 'R'.
        "PANGGIL FUNC UNTUK CEK BASEFILM HASIL PRODUKSI
        IF FLAGLOOPEXLENG NE '1'.
          PERFORM CEKBASEFILM USING IT_CHANGE-BATCHA CHANGING FLAG2.
        ENDIF.

      ENDIF.
      IF FLAG2 EQ '1'.
        LOOP AT SCREEN.
          IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
            SCREEN-INPUT = 1. " klo 0 disable 1 aktif
            MODIFY SCREEN.
          ENDIF.
        ENDLOOP.
      ELSE.

        LOOP AT SCREEN.
          IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
            SCREEN-INPUT = 1. " klo 0 disable 1 aktif
            MODIFY SCREEN.
          ENDIF.
        ENDLOOP.
      ENDIF.
    ENDIF.
  ENDIF.
  "1st/2sd -> scrap
  IF IT_CHANGE-CRITA EQ '1' OR IT_CHANGE-CRITA EQ '2'.
    IF IT_CHANGE-CRITB EQ 'S'.
      LOOP AT SCREEN.
        IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
          SCREEN-INPUT = 0. " klo 0 disable 1 aktif
          MODIFY SCREEN.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.
  "rw/rs/bf -> scrap
  IF IT_CHANGE-CRITA EQ 'R' OR IT_CHANGE-CRITA EQ 'B'.
    IF IT_CHANGE-CRITB EQ 'S'.
      LOOP AT SCREEN.
        IF SCREEN-NAME = 'IT_CHANGE-EXLENG'.
          SCREEN-INPUT = 0. " klo 0 disable 1 aktif
          MODIFY SCREEN.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDIF.
ENDMODULE.                    "TCHANGE_GET_LINES OUTPUT

*&SPWIZARD: INPUT MODULE FOR TC 'TCHANGE'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: MODIFY TABLE
MODULE TCHANGE_MODIFY INPUT.
  DATA:EXLENGFLAG TYPE C LENGTH 5,
       GRADEFLAG TYPE C LENGTH 30,
       IT_CHANGE_TEMP LIKE STANDARD TABLE OF IT_CHANGE WITH HEADER LINE.

  DATA: EXLENG_LAMA LIKE AUSP-ATWRT.

  CLEAR: EXLENG_LAMA.



*  IF FLAGLOOPEXLENG NE '1'.
  CLEAR IT_CHANGE_TEMP.
  REFRESH IT_CHANGE_TEMP.
  IT_CHANGE_TEMP[] = IT_CHANGE[].
*  ENDIF.

  FLAGLOOPEXLENG = '1'.



  IF IT_CHANGE-GRADEB NE ''.
    IT_CHANGE-EXLENG = IT_CHANGE-EXLENG.

    READ TABLE IT_GRADE WITH KEY VTVALUE = IT_CHANGE-GRADEB.
    IF SY-SUBRC EQ 0.
      CLEAR ATINN.
      PERFORM ATNAM USING 'ZZGRADE' CHANGING ATINN.
      SELECT SINGLE ATWTB INTO IT_CHANGE-DGRADE2
        FROM CAWNT
        JOIN CAWN ON CAWN~ATINN = CAWNT~ATINN AND CAWN~ATZHL = CAWNT~ATZHL
        WHERE CAWN~ATWRT = IT_CHANGE-GRADEB
        AND CAWN~ATINN = ATINN
        AND CAWNT~SPRAS EQ 'EN'.
      READ TABLE IT_CRITERIA WITH KEY VTLINENO = IT_GRADE-VTLINENO.
      IF SY-SUBRC EQ 0.
        CLEAR ATINN.
        PERFORM ATNAM USING 'ZZCRITERIA' CHANGING ATINN.
        IT_CHANGE-CRITB = IT_CRITERIA-VTVALUE.

        SELECT SINGLE ATWTB INTO IT_CHANGE-DCRITB
        FROM CAWNT
        JOIN CAWN ON CAWN~ATINN = CAWNT~ATINN AND CAWN~ATZHL = CAWNT~ATZHL
        WHERE CAWN~ATWRT = IT_CHANGE-CRITB
        AND CAWN~ATINN = ATINN
        AND CAWNT~SPRAS EQ 'EN'.
      ENDIF.
      IF IT_CHANGE-EXIDV IS NOT INITIAL.
        IF IT_CHANGE-CRITB EQ 'S'.
          CLEAR: IT_CHANGE-CRITB,IT_CHANGE-DGRADE2,IT_CHANGE-GRADEB,IT_CHANGE-DCRITB.
          MESSAGE  'Batch yang terikat HU tidak boleh memiliki criteria grade Scrap' TYPE 'I'.
*          REFRESH CONTROL 'TCHANGE' FROM SCREEN 0200.
          SET SCREEN 0.
        ENDIF.
      ENDIF.
*     EDIT REY 02/05/2018
      IF IT_CHANGE-CRITA EQ '1' OR IT_CHANGE-CRITA EQ '2'.
        IF IT_CHANGE-CRITB EQ 'R' OR IT_CHANGE-CRITB EQ 'B'.
          IF IT_CHANGE-EXLENG IS INITIAL.
            CONCATENATE 'Terjadi Kesalahan Batch' IT_CHANGE-BATCHA 'Tidak Memiliki Extra Length' INTO MSGEXLENG SEPARATED BY SPACE.
            MESSAGE MSGEXLENG TYPE 'I'.
            SET SCREEN 0.
          ENDIF.
        ENDIF.
      ENDIF.
    ELSE.
      CLEAR: IT_CHANGE-GRADEB,IT_CHANGE-CRITB.
      MESSAGE 'Grade tidak ditemukan!' TYPE 'I'.

    ENDIF.

*    CEK SLOC JR NA
    IF IT_CHANGE-CRITB EQ 'S'.
      DATA: FLAG_SLOC TYPE STRING,
            MSGSLOC2 TYPE STRING.
      PERFORM CHECK_SLOCJRNA USING IT_CHANGE-LGORT IT_CHANGE-WERKS CHANGING FLAG_SLOC.

      IF FLAG_SLOC EQ 'X'.
        CLEAR: IT_CHANGE-GRADEB,IT_CHANGE-CRITB.
        CONCATENATE 'Sloc Batch' IT_CHANGE-BATCHA 'Salah, Tidak Bisa Untuk di Kupas' INTO MSGSLOC2 SEPARATED BY SPACE.
        MESSAGE MSGSLOC2 TYPE 'I'.
*          REFRESH CONTROL 'TCHANGE' FROM SCREEN 0200.
        SET SCREEN 0.
      ENDIF.
    ENDIF.

  ENDIF.

  MODIFY IT_CHANGE
    INDEX TCHANGE-CURRENT_LINE.


  LOOP AT IT_CHANGE_TEMP WHERE BATCHA EQ IT_CHANGE-BATCHA.
    GRADEFLAG = IT_CHANGE_TEMP-GRADEB.
  ENDLOOP.




  IF GRADEFLAG NE IT_CHANGE-GRADEB .
    LOOP AT IT_CHANGE_TEMP WHERE BATCHA EQ IT_CHANGE-BATCHA.
      IF ( IT_CHANGE-CRITA EQ 'R' OR IT_CHANGE-CRITA EQ 'B' ) AND ( IT_CHANGE-CRITB EQ '1' OR IT_CHANGE-CRITB EQ '2' ).

        IF IT_CHANGE-CRITA EQ 'B' OR IT_CHANGE-CRITA EQ 'R'.
          "PANGGIL FUNC UNTUK CEK BASEFILM HASIL PRODUKSI

          PERFORM CEKBASEFILM USING IT_CHANGE-BATCHA CHANGING FLAG2.




        ENDIF.

      ELSE.
        PERFORM GET_EXLENGHT_LAMA USING IT_CHANGE-MATNR IT_CHANGE-BATCHA IT_CHANGE-WERKS CHANGING EXLENG_LAMA.

        CONDENSE EXLENG_LAMA.
        IT_CHANGE-EXLENG = EXLENG_LAMA.
      ENDIF.

    ENDLOOP.
    MODIFY IT_CHANGE
      INDEX TCHANGE-CURRENT_LINE.
  ENDIF.



ENDMODULE.                    "TCHANGE_MODIFY INPUT

*&SPWIZARD: INPUT MODUL FOR TC 'TCHANGE'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: MARK TABLE
MODULE TCHANGE_MARK INPUT.
  DATA: G_TCHANGE_WA2 LIKE LINE OF IT_CHANGE.
  IF TCHANGE-LINE_SEL_MODE = 1
  AND IT_CHANGE-BOX = 'X'.
    LOOP AT IT_CHANGE INTO G_TCHANGE_WA2
      WHERE BOX = 'X'.
      G_TCHANGE_WA2-BOX = ''.
      MODIFY IT_CHANGE
        FROM G_TCHANGE_WA2
        TRANSPORTING BOX.
    ENDLOOP.
  ENDIF.
  MODIFY IT_CHANGE
    INDEX TCHANGE-CURRENT_LINE
    TRANSPORTING BOX.
ENDMODULE.                    "TCHANGE_MARK INPUT

*&SPWIZARD: INPUT MODULE FOR TC 'TCHANGE'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: PROCESS USER COMMAND
MODULE TCHANGE_USER_COMMAND INPUT.
  OK_CODE = SY-UCOMM.
  PERFORM USER_OK_TC USING    'TCHANGE'
                              'IT_CHANGE'
                              'BOX'
                     CHANGING OK_CODE.
  SY-UCOMM = OK_CODE.

  CASE SY-UCOMM.
    WHEN '&F03'.
      LEAVE TO SCREEN 0.
  ENDCASE.

ENDMODULE.                    "TCHANGE_USER_COMMAND INPUT

*----------------------------------------------------------------------*
*   INCLUDE TABLECONTROL_FORMS                                         *
*----------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*&      Form  USER_OK_TC                                               *
*&---------------------------------------------------------------------*
FORM USER_OK_TC USING    P_TC_NAME TYPE DYNFNAM
                         P_TABLE_NAME
                         P_MARK_NAME
                CHANGING P_OK      LIKE SY-UCOMM.

*&SPWIZARD: BEGIN OF LOCAL DATA----------------------------------------*
  DATA: L_OK              TYPE SY-UCOMM,
        L_OFFSET          TYPE I.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

*&SPWIZARD: Table control specific operations                          *
*&SPWIZARD: evaluate TC name and operations                            *
  SEARCH P_OK FOR P_TC_NAME.
  IF SY-SUBRC <> 0.
    EXIT.
  ENDIF.
  L_OFFSET = STRLEN( P_TC_NAME ) + 1.
  L_OK = P_OK+L_OFFSET.
*&SPWIZARD: execute general and TC specific operations                 *
  CASE L_OK.
    WHEN 'INSR'.                      "insert row
      PERFORM FCODE_INSERT_ROW USING    P_TC_NAME
                                        P_TABLE_NAME.
      CLEAR P_OK.

    WHEN 'DELE'.                      "delete row
      PERFORM FCODE_DELETE_ROW USING    P_TC_NAME
                                        P_TABLE_NAME
                                        P_MARK_NAME.
      CLEAR P_OK.

    WHEN 'P--' OR                     "top of list
         'P-'  OR                     "previous page
         'P+'  OR                     "next page
         'P++'.                       "bottom of list
      PERFORM COMPUTE_SCROLLING_IN_TC USING P_TC_NAME
                                            L_OK.
      CLEAR P_OK.
    WHEN 'MARK'.                      "mark all filled lines
      PERFORM FCODE_TC_MARK_LINES USING P_TC_NAME
                                        P_TABLE_NAME
                                        P_MARK_NAME   .
      CLEAR P_OK.

    WHEN 'DMRK'.                      "demark all filled lines
      PERFORM FCODE_TC_DEMARK_LINES USING P_TC_NAME
                                          P_TABLE_NAME
                                          P_MARK_NAME .
      CLEAR P_OK.

  ENDCASE.

ENDFORM.                              " USER_OK_TC

*&---------------------------------------------------------------------*
*&      Form  FCODE_INSERT_ROW                                         *
*&---------------------------------------------------------------------*
FORM FCODE_INSERT_ROW
              USING    P_TC_NAME           TYPE DYNFNAM
                       P_TABLE_NAME             .

*&SPWIZARD: BEGIN OF LOCAL DATA----------------------------------------*
  DATA L_LINES_NAME       LIKE FELD-NAME.
  DATA L_SELLINE          LIKE SY-STEPL.
  DATA L_LASTLINE         TYPE I.
  DATA L_LINE             TYPE I.
  DATA L_TABLE_NAME       LIKE FELD-NAME.
  FIELD-SYMBOLS <TC>                 TYPE CXTAB_CONTROL.
  FIELD-SYMBOLS <TABLE>              TYPE STANDARD TABLE.
  FIELD-SYMBOLS <LINES>              TYPE I.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

  ASSIGN (P_TC_NAME) TO <TC>.

*&SPWIZARD: get the table, which belongs to the tc                     *
  CONCATENATE P_TABLE_NAME '[]' INTO L_TABLE_NAME. "table body
  ASSIGN (L_TABLE_NAME) TO <TABLE>.                "not headerline

*&SPWIZARD: get looplines of TableControl                              *
  CONCATENATE 'G_' P_TC_NAME '_LINES' INTO L_LINES_NAME.
  ASSIGN (L_LINES_NAME) TO <LINES>.

*&SPWIZARD: get current line                                           *
  GET CURSOR LINE L_SELLINE.
  IF SY-SUBRC <> 0.                   " append line to table
    L_SELLINE = <TC>-LINES + 1.
*&SPWIZARD: set top line                                               *
    IF L_SELLINE > <LINES>.
      <TC>-TOP_LINE = L_SELLINE - <LINES> + 1 .
    ELSE.
      <TC>-TOP_LINE = 1.
    ENDIF.
  ELSE.                               " insert line into table
    L_SELLINE = <TC>-TOP_LINE + L_SELLINE - 1.
    L_LASTLINE = <TC>-TOP_LINE + <LINES> - 1.
  ENDIF.
*&SPWIZARD: set new cursor line                                        *
  L_LINE = L_SELLINE - <TC>-TOP_LINE + 1.

*&SPWIZARD: insert initial line                                        *
  INSERT INITIAL LINE INTO <TABLE> INDEX L_SELLINE.
  <TC>-LINES = <TC>-LINES + 1.
*&SPWIZARD: set cursor                                                 *
  SET CURSOR LINE L_LINE.

ENDFORM.                              " FCODE_INSERT_ROW

*&---------------------------------------------------------------------*
*&      Form  FCODE_DELETE_ROW                                         *
*&---------------------------------------------------------------------*
FORM FCODE_DELETE_ROW
              USING    P_TC_NAME           TYPE DYNFNAM
                       P_TABLE_NAME
                       P_MARK_NAME   .

*&SPWIZARD: BEGIN OF LOCAL DATA----------------------------------------*
  DATA L_TABLE_NAME       LIKE FELD-NAME.

  FIELD-SYMBOLS <TC>         TYPE CXTAB_CONTROL.
  FIELD-SYMBOLS <TABLE>      TYPE STANDARD TABLE.
  FIELD-SYMBOLS <WA>.
  FIELD-SYMBOLS <MARK_FIELD>.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

  ASSIGN (P_TC_NAME) TO <TC>.

*&SPWIZARD: get the table, which belongs to the tc                     *
  CONCATENATE P_TABLE_NAME '[]' INTO L_TABLE_NAME. "table body
  ASSIGN (L_TABLE_NAME) TO <TABLE>.                "not headerline

*&SPWIZARD: delete marked lines                                        *
  DESCRIBE TABLE <TABLE> LINES <TC>-LINES.

  LOOP AT <TABLE> ASSIGNING <WA>.

*&SPWIZARD: access to the component 'FLAG' of the table header         *
    ASSIGN COMPONENT P_MARK_NAME OF STRUCTURE <WA> TO <MARK_FIELD>.

    IF <MARK_FIELD> = 'X'.
      DELETE <TABLE> INDEX SYST-TABIX.
      IF SY-SUBRC = 0.
        <TC>-LINES = <TC>-LINES - 1.
      ENDIF.
    ENDIF.
  ENDLOOP.

ENDFORM.                              " FCODE_DELETE_ROW

*&---------------------------------------------------------------------*
*&      Form  COMPUTE_SCROLLING_IN_TC
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_TC_NAME  name of tablecontrol
*      -->P_OK       ok code
*----------------------------------------------------------------------*
FORM COMPUTE_SCROLLING_IN_TC USING    P_TC_NAME
                                      P_OK.
*&SPWIZARD: BEGIN OF LOCAL DATA----------------------------------------*
  DATA L_TC_NEW_TOP_LINE     TYPE I.
  DATA L_TC_NAME             LIKE FELD-NAME.
  DATA L_TC_LINES_NAME       LIKE FELD-NAME.
  DATA L_TC_FIELD_NAME       LIKE FELD-NAME.

  FIELD-SYMBOLS <TC>         TYPE CXTAB_CONTROL.
  FIELD-SYMBOLS <LINES>      TYPE I.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

  ASSIGN (P_TC_NAME) TO <TC>.
*&SPWIZARD: get looplines of TableControl                              *
  CONCATENATE 'G_' P_TC_NAME '_LINES' INTO L_TC_LINES_NAME.
  ASSIGN (L_TC_LINES_NAME) TO <LINES>.


*&SPWIZARD: is no line filled?                                         *
  IF <TC>-LINES = 0.
*&SPWIZARD: yes, ...                                                   *
    L_TC_NEW_TOP_LINE = 1.
  ELSE.
*&SPWIZARD: no, ...                                                    *
    CALL FUNCTION 'SCROLLING_IN_TABLE'
      EXPORTING
        ENTRY_ACT             = <TC>-TOP_LINE
        ENTRY_FROM            = 1
        ENTRY_TO              = <TC>-LINES
        LAST_PAGE_FULL        = 'X'
        LOOPS                 = <LINES>
        OK_CODE               = P_OK
        OVERLAPPING           = 'X'
      IMPORTING
        ENTRY_NEW             = L_TC_NEW_TOP_LINE
      EXCEPTIONS
*       NO_ENTRY_OR_PAGE_ACT  = 01
*       NO_ENTRY_TO           = 02
*       NO_OK_CODE_OR_PAGE_GO = 03
        OTHERS                = 0.
  ENDIF.

*&SPWIZARD: get actual tc and column                                   *
  GET CURSOR FIELD L_TC_FIELD_NAME
             AREA  L_TC_NAME.

  IF SYST-SUBRC = 0.
    IF L_TC_NAME = P_TC_NAME.
*&SPWIZARD: et actual column                                           *
      SET CURSOR FIELD L_TC_FIELD_NAME LINE 1.
    ENDIF.
  ENDIF.

*&SPWIZARD: set the new top line                                       *
  <TC>-TOP_LINE = L_TC_NEW_TOP_LINE.


ENDFORM.                              " COMPUTE_SCROLLING_IN_TC

*&---------------------------------------------------------------------*
*&      Form  FCODE_TC_MARK_LINES
*&---------------------------------------------------------------------*
*       marks all TableControl lines
*----------------------------------------------------------------------*
*      -->P_TC_NAME  name of tablecontrol
*----------------------------------------------------------------------*
FORM FCODE_TC_MARK_LINES USING P_TC_NAME
                               P_TABLE_NAME
                               P_MARK_NAME.
*&SPWIZARD: EGIN OF LOCAL DATA-----------------------------------------*
  DATA L_TABLE_NAME       LIKE FELD-NAME.

  FIELD-SYMBOLS <TC>         TYPE CXTAB_CONTROL.
  FIELD-SYMBOLS <TABLE>      TYPE STANDARD TABLE.
  FIELD-SYMBOLS <WA>.
  FIELD-SYMBOLS <MARK_FIELD>.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

  ASSIGN (P_TC_NAME) TO <TC>.

*&SPWIZARD: get the table, which belongs to the tc                     *
  CONCATENATE P_TABLE_NAME '[]' INTO L_TABLE_NAME. "table body
  ASSIGN (L_TABLE_NAME) TO <TABLE>.                "not headerline

*&SPWIZARD: mark all filled lines                                      *
  LOOP AT <TABLE> ASSIGNING <WA>.

*&SPWIZARD: access to the component 'FLAG' of the table header         *
    ASSIGN COMPONENT P_MARK_NAME OF STRUCTURE <WA> TO <MARK_FIELD>.

    <MARK_FIELD> = 'X'.
  ENDLOOP.
ENDFORM.                                          "fcode_tc_mark_lines

*&---------------------------------------------------------------------*
*&      Form  FCODE_TC_DEMARK_LINES
*&---------------------------------------------------------------------*
*       demarks all TableControl lines
*----------------------------------------------------------------------*
*      -->P_TC_NAME  name of tablecontrol
*----------------------------------------------------------------------*
FORM FCODE_TC_DEMARK_LINES USING P_TC_NAME
                                 P_TABLE_NAME
                                 P_MARK_NAME .
*&SPWIZARD: BEGIN OF LOCAL DATA----------------------------------------*
  DATA L_TABLE_NAME       LIKE FELD-NAME.

  FIELD-SYMBOLS <TC>         TYPE CXTAB_CONTROL.
  FIELD-SYMBOLS <TABLE>      TYPE STANDARD TABLE.
  FIELD-SYMBOLS <WA>.
  FIELD-SYMBOLS <MARK_FIELD>.
*&SPWIZARD: END OF LOCAL DATA------------------------------------------*

  ASSIGN (P_TC_NAME) TO <TC>.

*&SPWIZARD: get the table, which belongs to the tc                     *
  CONCATENATE P_TABLE_NAME '[]' INTO L_TABLE_NAME. "table body
  ASSIGN (L_TABLE_NAME) TO <TABLE>.                "not headerline

*&SPWIZARD: demark all filled lines                                    *
  LOOP AT <TABLE> ASSIGNING <WA>.

*&SPWIZARD: access to the component 'FLAG' of the table header         *
    ASSIGN COMPONENT P_MARK_NAME OF STRUCTURE <WA> TO <MARK_FIELD>.

    <MARK_FIELD> = SPACE.
  ENDLOOP.
ENDFORM.                                          "fcode_tc_mark_lines
*&---------------------------------------------------------------------*
*&      Form  GETDATA_CHANGE
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM GETDATA_CHANGE .
  DATA : BEGIN OF VALID OCCURS 0,
        CHARG LIKE MCHB-CHARG,
        VENUM TYPE C LENGTH 10,
        NUM TYPE I,
        TEXT(200).
  DATA : END OF VALID.
  DATA : ANS TYPE C,
        FLAG TYPE STRING.
  DATA :VALID1 LIKE STANDARD TABLE OF VALID WITH HEADER LINE,
        VALID2 LIKE STANDARD TABLE OF VALID WITH HEADER LINE,
        VALID3 LIKE STANDARD TABLE OF VALID WITH HEADER LINE,
        POP LIKE STANDARD TABLE OF SPOPLI WITH HEADER LINE.
  CLEAR : TBATCH, MSG,VALID,VALID2,VALID3, ANS, POP.
  REFRESH : TBATCH,VALID,VALID2,VALID3,POP.

  SELECT CHARG INTO CORRESPONDING FIELDS OF TABLE VALID
    FROM MCHB
    WHERE  CHARG IN P_CHARG2 AND
    ( CLABS LE 0 AND CUMLM LE 0 AND CINSM LE 0 AND CEINM LE 0 AND CSPEM LE 0 AND CRETM LE 0 ).
  SELECT CHARG INTO CORRESPONDING FIELDS OF TABLE VALID1
    FROM MCHB
    WHERE  CHARG IN P_CHARG2 AND
    ( CLABS > 0 OR CUMLM > 0 OR CINSM > 0 OR CEINM > 0 OR CSPEM > 0 OR CRETM > 0 ).
  LOOP AT VALID1.
    READ TABLE VALID WITH KEY CHARG = VALID1-CHARG.
    IF SY-SUBRC EQ 0.
      DELETE VALID WHERE CHARG = VALID1-CHARG.
    ENDIF.
  ENDLOOP.
  SORT VALID BY CHARG ASCENDING.
  DELETE ADJACENT DUPLICATES FROM VALID COMPARING CHARG.

  SELECT CHARG INTO CORRESPONDING FIELDS OF TABLE VALID3
    FROM MSKA
    WHERE  CHARG IN P_CHARG2 AND
    ( KALAB > 0 OR KAINS > 0 OR KASPE > 0 ).
  SORT VALID3 BY CHARG ASCENDING.
  DELETE ADJACENT DUPLICATES FROM VALID3 COMPARING CHARG.

  SELECT MCHB~MATNR MCHB~WERKS MCHB~LGORT MCHB~CHARG INTO (IT_CHANGE-MATNR,IT_CHANGE-WERKS, IT_CHANGE-LGORT, IT_CHANGE-BATCHA)
    FROM MCHB
    WHERE
    MCHB~CHARG IN P_CHARG2 AND
    ( CLABS > 0 OR CUMLM > 0 OR CINSM > 0 OR CEINM > 0 OR CSPEM > 0 OR CRETM > 0 ).
    APPEND IT_CHANGE.
  ENDSELECT.
  LOOP AT IT_CHANGE.
    IT_CHANGE-GRADEB = P_GRADE2.
    IT_CHANGE-NMEMO = P_NMEMO2.
    IT_CHANGE-AUTHOR = P_AUTH2.
    IT_CHANGE-RSLOC = P_LGORT2.

    CALL FUNCTION 'VB_INIT'
      EXPORTING
        INIT_RESET = 'X'.
    CALL FUNCTION 'VB_BATCH_GET_DETAIL'
      EXPORTING
        MATNR              = IT_CHANGE-MATNR
        CHARG              = IT_CHANGE-BATCHA
        WERKS              = IT_CHANGE-WERKS
        GET_CLASSIFICATION = 'X'
      TABLES
        CHAR_OF_BATCH      = TBATCH
      EXCEPTIONS
        NO_MATERIAL        = 1
        NO_BATCH           = 2
        NO_PLANT           = 3
        MATERIAL_NOT_FOUND = 4
        PLANT_NOT_FOUND    = 5
        NO_AUTHORITY       = 6
        BATCH_NOT_EXIST    = 7
        LOCK_ON_BATCH      = 8
        OTHERS             = 9.
    IF SY-SUBRC <> 0.
* Implement suitable error handling here
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCODE'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-TYPE = TBATCH-ATWTB.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZLENGTH'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-LENGHT = TBATCH-ATWTB.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZWIDTH'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-WIDTH = TBATCH-ATWTB.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCONVERSIONROLLKG'.
    IF SY-SUBRC EQ 0.
      CONDENSE TBATCH-ATWTB.
      SPLIT TBATCH-ATWTB AT SPACE INTO IT_CHANGE-WEIGHT TEMP.
      SPLIT TBATCH-ATWTB AT SPACE INTO IT_CHANGE-GPMNG IT_CHANGE-MEINS.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZNOMORROLL'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-NOROLA = TBATCH-ATWTB.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZGRADE'.
    IF SY-SUBRC EQ 0.
      CLEAR ATINN.
      PERFORM ATNAM USING TBATCH-ATNAM CHANGING ATINN.
      SELECT SINGLE CAWN~ATWRT INTO IT_CHANGE-GRADEA
          FROM CAWN
          JOIN CAWNT ON  CAWNT~ATINN = CAWN~ATINN
          AND CAWNT~ATZHL = CAWN~ATZHL
          WHERE CAWNT~ATWTB = TBATCH-ATWTB
          AND CAWN~ATINN = ATINN.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZCRITERIA'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-DCRITA = TBATCH-ATWTB.
      CLEAR ATINN.
      PERFORM ATNAM USING TBATCH-ATNAM CHANGING ATINN.
      SELECT SINGLE CAWN~ATWRT INTO IT_CHANGE-CRITA
          FROM CAWN
          JOIN CAWNT ON  CAWNT~ATINN = CAWN~ATINN
          AND CAWNT~ATZHL = CAWN~ATZHL
          WHERE CAWNT~ATWTB = TBATCH-ATWTB
          AND CAWN~ATINN = ATINN.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZGRADE'.
    IF SY-SUBRC EQ 0.
      IT_CHANGE-DGRADE = TBATCH-ATWTB.
    ENDIF.
    SELECT SINGLE VENUM INTO IT_CHANGE-VENUM
      FROM VEPO
      WHERE CHARG = IT_CHANGE-BATCHA.
    SELECT SINGLE VEKP~UEVEL VEKP~EXIDV VEKP~MAGRV INTO (IT_CHANGE-UEVEL, IT_CHANGE-EXIDV, IT_CHANGE-MAGRV)
      FROM VEKP
      WHERE VEKP~VENUM = IT_CHANGE-VENUM
      AND VEKP~STATUS NOT IN ('0050','0001','0060').
    IF IT_CHANGE-UEVEL IS NOT INITIAL AND IT_CHANGE-MAGRV EQ 'BOX'.
      SELECT SINGLE VEKP~UEVEL VEKP~EXIDV INTO (IT_CHANGE-UEVEL, IT_CHANGE-EXIDV)
      FROM VEKP
      WHERE VEKP~VENUM = IT_CHANGE-UEVEL
      AND VEKP~STATUS NOT IN ('0050','0001','0060').
    ENDIF.

    SHIFT IT_CHANGE-EXIDV LEFT DELETING LEADING '0'.
    SELECT SINGLE SPRNT INTO IT_CHANGE-SPRNT
      FROM ZBATCHISTORY
      WHERE ZBATCHISTORY~CHARG = IT_CHANGE-BATCHA.

    MODIFY IT_CHANGE.
  ENDLOOP.
  CALL FUNCTION 'CARD_TABLE_READ_ENTRIES'
    EXPORTING
      VAR_TABLE       = 'ZZGRADE'
    TABLES
      VAR_TAB_ENTRIES = IT_GRADE
    EXCEPTIONS
      ERROR           = 1
      OTHERS          = 2.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
  IT_CRITERIA[] = IT_GRADE[].
  DELETE IT_CRITERIA WHERE VTCHARACT EQ 'ZZGRADE'.
  DELETE IT_GRADE WHERE VTCHARACT EQ 'ZZCRITERIA'.
  VENUM = 1.

  CLEAR VEPO.
  VEPO = LINES( VALID ).
  IF VEPO GT 0 AND VENUM EQ 1.
    FLAG = '1'.
  ENDIF.

  CLEAR: POP.
  CLEAR VEPO.
  REFRESH: POP.
  VEPO = LINES( VALID3 ).
  IF VEPO GT 0 AND VENUM EQ 1.
    FLAG = '2'.
  ENDIF.

  IF FLAG EQ '1'.
    LOOP AT VALID.
      CONCATENATE 'Batch' VALID-CHARG 'tidak memiliki stock.' INTO POP-VAROPTION SEPARATED BY SPACE.
      DELETE IT_CHANGE WHERE BATCHA = VALID-CHARG.
      APPEND POP.
    ENDLOOP.
    CALL FUNCTION 'POPUP_TO_DISPLAY_TEXT_LO'
      EXPORTING
        TITEL        = 'Information'
        TEXTLINE1    = 'Informasi Batch Stok!'
        TEXTLINE2    = ' '
        TEXTLINE3    = POP-VAROPTION
        START_COLUMN = 15
        START_ROW    = 6.
    STOP.
  ELSEIF FLAG EQ '2'.
    LOOP AT VALID3.
      CONCATENATE 'Batch' VALID3-CHARG 'masih terikat dengan SO.' INTO POP-VAROPTION SEPARATED BY SPACE.
      DELETE IT_CHANGE WHERE BATCHA = VALID3-CHARG.
      APPEND POP.
    ENDLOOP.
    CALL FUNCTION 'POPUP_TO_DISPLAY_TEXT_LO'
      EXPORTING
        TITEL        = 'Information'
        TEXTLINE1    = 'Informasi Batch SO!'
        TEXTLINE2    = ' '
        TEXTLINE3    = POP-VAROPTION
        START_COLUMN = 15
        START_ROW    = 6.
    STOP.
  ENDIF.

  CLEAR VEPO.
  VEPO = LINES( IT_CHANGE ).
  IF VENUM EQ 1.
    IF VEPO EQ 0.
      MESSAGE 'Batch Tidak Ditemukan!' TYPE 'I'.
    ELSE.
      PERFORM FILLDATA.
      CALL SCREEN 200.
    ENDIF.
  ENDIF.
ENDFORM.                    " GETDATA_CHANGE
*&---------------------------------------------------------------------*
*&      Module  STATUS_0200  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE STATUS_0200 OUTPUT.
  DATA: F_FCODE TYPE TABLE OF SY-UCOMM.
  APPEND 'EXIT' TO F_FCODE.
  SET PF-STATUS 'MAIN100' EXCLUDING F_FCODE.

ENDMODULE.                 " STATUS_0200  OUTPUT
*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0200  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE USER_COMMAND_0200 INPUT.
  DATA : CHOISE LIKE SY-TABIX,
         INSP LIKE QALS-PRUEFLOS,
         NOREF LIKE ZQM_LOG_GS-PRUEFLOSREF,
         JLH TYPE I,
         HU LIKE VEKP-EXIDV,
         BA LIKE LIPS-CHARG,
         CRI TYPE C LENGTH 30.
  RANGES: THU FOR VEKP-EXIDV.
  DATA: V_COUNT TYPE I.
  CLEAR V_COUNT.

  CASE SY-UCOMM.
    WHEN 'PRINT'.
      REFRESH THU.
      LOOP AT IT_CHANGE WHERE CHK = 'X'.
*        REFRESH THU.
        THU-SIGN   = 'I'.
        THU-OPTION = 'EQ'.
        THU-LOW = IT_CHANGE-BATCHA.
        APPEND THU.
      ENDLOOP.
      SUBMIT ZMMR_LABELROL WITH  P_CHARG IN THU
*                            WITH V_COPIES = 1
      AND RETURN.
      LOOP AT THU.
        UPDATE ZBATCHISTORY SET SPRNT = 'X'
        WHERE ZBATCHISTORY~CHARG = THU-LOW.
      ENDLOOP.
    WHEN 'SELALL'.
      LOOP AT IT_CHANGE WHERE CHK NE 'X'.
        IT_CHANGE-CHK = 'X'.
        MODIFY IT_CHANGE.
      ENDLOOP.
    WHEN 'DESALL'.
      LOOP AT IT_CHANGE WHERE CHK EQ 'X'.
        IT_CHANGE-CHK = ''.
        MODIFY IT_CHANGE.
      ENDLOOP.
    WHEN 'BACK'.
      LEAVE TO SCREEN 0.
    WHEN '%F03'.
      LEAVE TO SCREEN 0.
    WHEN 'CHANGE'.
      PERFORM CHANGE.

  ENDCASE.
ENDMODULE.                 " USER_COMMAND_0200  INPUT
*&---------------------------------------------------------------------*
*&      Module  RSLOCF4_HELP  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE RSLOCF4_HELP INPUT.
  CLEAR : ITHELP.
  REFRESH: ITHELP.
  CALL FUNCTION 'DYNP_GET_STEPL'
    IMPORTING
      POVSTEPL = V_DYNINDEX.
  READ TABLE IT_CHANGE INDEX V_DYNINDEX.
  IF IT_CHANGE-WERKS IS INITIAL.
    MESSAGE 'Plant Kosong!' TYPE 'I'.
  ELSE.
    CASE IT_CHANGE-WERKS.
      WHEN '1000'.
        SELECT DISTINCT WERKS ZRRLGORT AS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
          FROM ZTMAP_SLOCRR
          WHERE ZTMAP_SLOCRR~WERKS = '1000'.
        CLEAR : ITHELP.
        ITHELP-WERKS = '1000'.
        ITHELP-LGORT = '1815'.
        APPEND ITHELP.
      WHEN '2000'.
        SELECT DISTINCT WERKS ZRRLGORT AS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
          FROM ZTMAP_SLOCRR
          WHERE ZTMAP_SLOCRR~WERKS = '2000'.
        CLEAR : ITHELP.
        ITHELP-WERKS = '2000'.
        ITHELP-LGORT = '2815'.
        APPEND ITHELP.
    ENDCASE.
    LOOP AT ITHELP.
      SELECT SINGLE LGOBE INTO ITHELP-LGOBE
        FROM T001L
        WHERE WERKS = ITHELP-WERKS
        AND LGORT = ITHELP-LGORT.
      MODIFY ITHELP.
    ENDLOOP.
    SORT ITHELP BY WERKS LGORT ASCENDING.
    CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
      EXPORTING
        RETFIELD        = 'LGORT'
        DYNPPROG        = SY-CPROG
        DYNPNR          = SY-DYNNR
        DYNPROFIELD     = 'IT_CHANGE-RSLOC'
        STEPL           = V_DYNINDEX
        VALUE_ORG       = 'S'
      TABLES
        VALUE_TAB       = ITHELP
      EXCEPTIONS
        PARAMETER_ERROR = 1
        NO_VALUES_FOUND = 2
        OTHERS          = 3.
    IF SY-SUBRC <> 0.
* Implement suitable error handling here
    ENDIF.


  ENDIF.
ENDMODULE.                 " RSLOCF4_HELP  INPUT
*&---------------------------------------------------------------------*
*&      Module  STATUS_0300  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE STATUS_0300 OUTPUT.
  DATA: LL_FCODE TYPE TABLE OF SY-UCOMM.
  APPEND 'CHANGE' TO LL_FCODE.
  APPEND 'EXIT' TO LL_FCODE.
  APPEND 'SELALL' TO LL_FCODE.
  APPEND 'DESALL' TO LL_FCODE.
  APPEND 'PRINT' TO LL_FCODE.
  SET PF-STATUS 'MAIN100' EXCLUDING LL_FCODE.
*  SET TITLEBAR 'xxx'.

ENDMODULE.                 " STATUS_0300  OUTPUT
*&---------------------------------------------------------------------*
*&      Module  USER_COMMAND_0300  INPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE USER_COMMAND_0300 INPUT.
  CLEAR FLAG.
  CASE SY-UCOMM.
    WHEN 'YES'.
      FLAG = 'Y'.
      LEAVE TO SCREEN 0.
    WHEN 'KALUAR'.
      FLAG = 'N'.
      LEAVE TO SCREEN 0.
  ENDCASE.
ENDMODULE.                 " USER_COMMAND_0300  INPUT

*&SPWIZARD: OUTPUT MODULE FOR TC 'TPOP'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: UPDATE LINES FOR EQUIVALENT SCROLLBAR
MODULE TPOP_CHANGE_TC_ATTR OUTPUT.
  DESCRIBE TABLE U_CHANGE LINES TPOP-LINES.
ENDMODULE.                    "TPOP_CHANGE_TC_ATTR OUTPUT

*&SPWIZARD: OUTPUT MODULE FOR TC 'TPOP'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: GET LINES OF TABLECONTROL
MODULE TPOP_GET_LINES OUTPUT.
  G_TPOP_LINES = SY-LOOPC.
ENDMODULE.                    "TPOP_GET_LINES OUTPUT

*&SPWIZARD: INPUT MODULE FOR TC 'TPOP'. DO NOT CHANGE THIS LINE!
*&SPWIZARD: PROCESS USER COMMAND
MODULE TPOP_USER_COMMAND INPUT.
  OK_CODE = SY-UCOMM.
  PERFORM USER_OK_TC USING    'TPOP'
                              'U_CHANGE'
                              ' '
                     CHANGING OK_CODE.
  SY-UCOMM = OK_CODE.
ENDMODULE.                    "TPOP_USER_COMMAND INPUT
*&---------------------------------------------------------------------*
*&      Form  CHANGE_GRADE
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM CHANGE_GRADE .
*  DATA : TCHARG LIKE MSEG-CHARG.
  CLEAR :  V_TYPE,TCHARG.
  CLEAR : ZCHAR. REFRESH : ZCHAR.
  REFRESH REPORT.
  LOOP AT U_CHANGE.
*    BREAK-POINT.
    CLEAR DSTATUS.
    IF ( U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2' ) AND ( U_CHANGE-CRITB EQ 'B' OR U_CHANGE-CRITB EQ 'R' OR U_CHANGE-CRITB EQ 'S' ) .
      PERFORM CALL_ZPP006.
    ENDIF.
    IF U_CHANGE-CRITA EQ 'R'  AND ( U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2' ) .
      PERFORM CALL_ZPP006.
    ENDIF.
    IF U_CHANGE-CRITA EQ 'B' AND ( U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2' ).
      PERFORM CALL_ZPP006.
    ENDIF.
    CHECK DSTATUS NE 'E'.
    REFRESH IT_MSEG.
    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG
      FROM MSEG
      JOIN AUFK ON AUFK~AUFNR = MSEG~AUFNR
      WHERE MSEG~CHARG = U_CHANGE-BATCHA
      AND MSEG~BWART IN ('261', '262' )
      AND AUFK~AUART IN ('ZBS1', 'ZBS2').
    REFRESH DEL_MSEG.
    DEL_MSEG[] = IT_MSEG[].
    LOOP AT DEL_MSEG WHERE SMBLN IS NOT INITIAL.
      DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-SMBLN.
      DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-MBLNR.
    ENDLOOP.
    CLEAR : WA_MSEG,TCHARG.
    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
    REFRESH : IT_MSEG, DEL_MSEG.
    IF WA_MSEG-AUFNR IS NOT INITIAL.
      SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG FROM MSEG
        WHERE AUFNR = WA_MSEG-AUFNR
        AND BWART IN ('101', '102' ).
      DEL_MSEG[] = IT_MSEG[].
      LOOP AT DEL_MSEG WHERE SMBLN IS NOT INITIAL.
        DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-SMBLN.
        DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-MBLNR.
      ENDLOOP.
    ENDIF.
    CLEAR : U_CHANGE-NCHARG,WA_MSEG.
    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
    U_CHANGE-NCHARG = WA_MSEG-CHARG.
    IF U_CHANGE-NCHARG IS NOT INITIAL.
      U_CHANGE-POAJDS = WA_MSEG-AUFNR.
      TCHARG = U_CHANGE-NCHARG.
      CLEAR MSG1.
      CONCATENATE 'PO Adjustment yang terbentuk adalah  ' WA_MSEG-AUFNR INTO MSG1 SEPARATED BY SPACE.
    ELSE.
      TCHARG = U_CHANGE-BATCHA.
    ENDIF.

    PERFORM VB_GD_TAB USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.

    DELETE ZCHAR WHERE CHARACT = 'ZZGRADE'.
    DELETE ZCHAR WHERE CHARACT = 'ZZCRITERIA'.

    ZCHAR-CHARACT = 'ZZGRADE'.
    MOVE U_CHANGE-GRADEB TO ZCHAR-VALUE_CHAR.
    CONDENSE ZCHAR-VALUE_CHAR.
    APPEND ZCHAR.
    ZCHAR-CHARACT = 'ZZCRITERIA'.
    MOVE U_CHANGE-CRITB TO ZCHAR-VALUE_CHAR.
    CONDENSE ZCHAR-VALUE_CHAR.
    APPEND ZCHAR.
    PERFORM CHG_CHAR USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.
*    BREAK-POINT.
*    DSTATUS = 'X'. " JANGAN LUPA DI HAPUS YAHH!!!
    IF DSTATUS EQ 'X'.
      IF ( U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2' ) AND ( U_CHANGE-CRITB EQ 'B' OR U_CHANGE-CRITB EQ 'R' ) .
        PERFORM CANCELZPP006 USING U_CHANGE-BATCHA.
        PERFORM CANCELZPP006 USING U_CHANGE-NCHARG.
      ENDIF.
      IF U_CHANGE-CRITA EQ 'R'  AND ( U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2' ) .
        PERFORM CANCELZPP006 USING U_CHANGE-BATCHA.
        PERFORM CANCELZPP006 USING U_CHANGE-NCHARG.
      ENDIF.
      IF U_CHANGE-CRITA EQ 'B' AND U_CHANGE-CRITB NE 'B'.
        PERFORM CANCELZPP006 USING U_CHANGE-BATCHA.
        PERFORM CANCELZPP006 USING U_CHANGE-NCHARG.
      ENDIF.
    ENDIF.
    CHECK DSTATUS NE 'E'.
    IF U_CHANGE-CRITB EQ 'S'.
      CLEAR: V_MATNR.
      DO 20 TIMES.
        SELECT SINGLE MATNR
          INTO V_MATNR
          FROM MCH1
         WHERE MATNR = U_CHANGE-MATNR AND CHARG = TCHARG."P_CHARG.
        IF SY-SUBRC NE 0.
          WAIT UP TO 1 SECONDS.
        ELSE.
*      EXIT.
          CALL FUNCTION 'ENQUEUE_EMMCH1E'
            EXPORTING
              MATNR          = U_CHANGE-MATNR
              CHARG          = TCHARG "P_CHARG
            EXCEPTIONS
              FOREIGN_LOCK   = 2
              SYSTEM_FAILURE = 3.

          IF SY-SUBRC  NE 0.
            WAIT UP TO 1 SECONDS.
          ELSE.
            CALL FUNCTION 'DEQUEUE_EMMCH1E'
              EXPORTING
                MATNR = U_CHANGE-MATNR
                CHARG = TCHARG."P_CHARG
            EXIT.
          ENDIF.
        ENDIF.
      ENDDO.
      CALL FUNCTION 'DEQUEUE_ALL'
        EXPORTING
          _SYNCHRON = 'X'.
      PERFORM CSRAP.
    ENDIF.
    IF DSTATUS NE 'E'.
      PERFORM GET_NOROLL USING U_CHANGE-MATNR U_CHANGE-WERKS TCHARG U_CHANGE-LGORT CHANGING U_CHANGE-NOROLB.
      PERFORM UPDATE_HISTORY.
    ENDIF.
    CLEAR DSTATUS.
    MODIFY U_CHANGE.
  ENDLOOP.
ENDFORM.                    " CHANGE_GRADE
*&---------------------------------------------------------------------*
*&      Form  BDC_DYNPRO
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->PROG       text
*      -->SCR        text
*----------------------------------------------------------------------*
FORM BDC_DYNPRO USING PROG SCR.
  CLEAR IT_BDCDATA.
  IT_BDCDATA-PROGRAM = PROG.
  IT_BDCDATA-DYNPRO  = SCR.
  IT_BDCDATA-DYNBEGIN = 'X'.
  APPEND IT_BDCDATA.
ENDFORM.                    "BDC_DYNPRO
*&---------------------------------------------------------------------*
*&      Form  BDC_FIELD
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->FNAM       text
*      -->FVAL       text
*----------------------------------------------------------------------*
FORM BDC_FIELD USING FNAM FVAL.
  CLEAR IT_BDCDATA.
  IT_BDCDATA-FNAM = FNAM.
  IT_BDCDATA-FVAL  = FVAL.
  APPEND IT_BDCDATA.
ENDFORM.                    "BDC_FIELD
*&---------------------------------------------------------------------*
*&      Form  UPDATE_HISTORY
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM UPDATE_HISTORY .
  DATA : V_BCHNO LIKE ZBATCHISTORY-BCHNO,
        V_TERMINALID LIKE USR41-TERMINAL.
  CLEAR : WA_HISTORY, V_BCHNO,V_TERMINALID.
  CLEAR : TBATCH.
  REFRESH : TBATCH.

  CALL FUNCTION 'TERMINAL_ID_GET'
    EXPORTING
      USERNAME             = SY-UNAME
    IMPORTING
      TERMINAL             = V_TERMINALID
    EXCEPTIONS
      MULTIPLE_TERMINAL_ID = 1
      NO_TERMINAL_FOUND    = 2
      OTHERS               = 3.
  IF SY-SUBRC <> 0.
*    MESSAGE 'Terminal ID not Valid Insert history failed.' TYPE 'E'.
  ENDIF.

  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = U_CHANGE-MATNR
      CHARG              = TCHARG
      WERKS              = U_CHANGE-WERKS
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = TBATCH
    EXCEPTIONS
      NO_MATERIAL        = 1
      NO_BATCH           = 2
      NO_PLANT           = 3
      MATERIAL_NOT_FOUND = 4
      PLANT_NOT_FOUND    = 5
      NO_AUTHORITY       = 6
      BATCH_NOT_EXIST    = 7
      LOCK_ON_BATCH      = 8
      OTHERS             = 9.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.


  SELECT MAX( BCHNO ) INTO V_BCHNO FROM ZBATCHISTORY.
  ADD 1 TO V_BCHNO.

  READ TABLE TBATCH WITH KEY ATNAM = 'ZZGRADE'.
  IF SY-SUBRC EQ 0.
    U_CHANGE-DGRADE2 = TBATCH-ATWTB.
  ENDIF.

*  *    get new batch
*    REFRESH IT_MSEG.
*    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG
*      FROM MSEG
*      JOIN AUFK ON AUFK~AUFNR = MSEG~AUFNR
*      WHERE MSEG~CHARG = U_CHANGE-BATCHA
*      AND MSEG~BWART IN ('261', '262' )
*      AND AUFK~AUART IN ('ZBS1', 'ZBS2').
*    LOOP AT IT_MSEG WHERE SMBLN IS NOT INITIAL.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-SMBLN.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-MBLNR.
*    ENDLOOP.
*    CLEAR : WA_MSEG.
*    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
*    REFRESH IT_MSEG.
*    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG FROM MSEG
*      WHERE AUFNR = WA_MSEG-AUFNR
*      AND BWART IN ('101', '102' ).
*    LOOP AT IT_MSEG WHERE SMBLN IS NOT INITIAL.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-SMBLN.
*      DELETE IT_MSEG WHERE MBLNR = IT_MSEG-MBLNR.
*    ENDLOOP.
*    CLEAR : WA_HISTORY-NCHARG,WA_MSEG.
*    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
*    WA_HISTORY-NCHARG = WA_MSEG-CHARG.
  CLEAR TBATCH.
  REFRESH TBATCH.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL' "
         EXPORTING
           MATNR = U_CHANGE-MATNR
           CHARG = U_CHANGE-NCHARG
           WERKS = U_CHANGE-WERKS                    " t001w-werks
           GET_CLASSIFICATION = 'X'       " am07m-xselk
         TABLES
           CHAR_OF_BATCH = TBATCH
         EXCEPTIONS
          NO_MATERIAL              = 1
          NO_BATCH                 = 2
          NO_PLANT                 = 3
          MATERIAL_NOT_FOUND       = 4
          PLANT_NOT_FOUND          = 5
          NO_AUTHORITY             = 6
          BATCH_NOT_EXIST          = 7
          LOCK_ON_BATCH            = 8
          OTHERS                   = 9.

  READ TABLE TBATCH WITH KEY ATNAM = 'ZZLENGTH'.
  IF SY-SUBRC EQ 0.
    WA_HISTORY-NLENGHT = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZCONVERSIONROLLKG'.
  IF SY-SUBRC EQ 0.
*      IZBATCHISTORY-WEIGHT = TBATCH-ATWTB.
    CONDENSE TBATCH-ATWTB.
    SPLIT TBATCH-ATWTB AT SPACE INTO WA_HISTORY-NWEIGHT TEMP.
  ENDIF.


  WA_HISTORY-MANDT = SY-MANDT.
  WA_HISTORY-BCHNO = V_BCHNO.
  WA_HISTORY-DTYPE = V_TYPE.
  WA_HISTORY-CHARG = U_CHANGE-BATCHA.
  WA_HISTORY-NCHARG = U_CHANGE-NCHARG.
  WA_HISTORY-GRADE = U_CHANGE-GRADEA.
  WA_HISTORY-GRADE2 = U_CHANGE-GRADEB.
  WA_HISTORY-UNAME = SY-UNAME.
  WA_HISTORY-AUTHR = U_CHANGE-AUTHOR.
  WA_HISTORY-BUDAT = SY-DATUM.
  WA_HISTORY-UZEIT = SY-UZEIT.
  WA_HISTORY-NMEMO = U_CHANGE-NMEMO.
  WA_HISTORY-NOTES = V_TERMINALID.
  WA_HISTORY-MATNR = U_CHANGE-MATNR.
  WA_HISTORY-WERKS = U_CHANGE-WERKS.
  WA_HISTORY-CRITERIA = U_CHANGE-CRITA.
  WA_HISTORY-CRITERIA2 = U_CHANGE-CRITB.
  WA_HISTORY-NOROLL = U_CHANGE-NOROLA.
  WA_HISTORY-RSLOC = U_CHANGE-RSLOC.
  WA_HISTORY-LGORT = U_CHANGE-LGORT.
  WA_HISTORY-GPMNG = U_CHANGE-GPMNG.
  WA_HISTORY-MEINS = U_CHANGE-MEINS.
  WA_HISTORY-NOROLL2 = U_CHANGE-NOROLB.
  WA_HISTORY-DGRADE  = U_CHANGE-DGRADE.
  WA_HISTORY-DGRADE2 = U_CHANGE-DGRADE2.
  WA_HISTORY-DCRITA  = U_CHANGE-DCRITA.
  WA_HISTORY-DCRITB = U_CHANGE-DCRITB.
  WA_HISTORY-EXIDV = U_CHANGE-EXIDV.
  INSERT ZBATCHISTORY FROM WA_HISTORY.
  COMMIT WORK AND WAIT.
ENDFORM.                    " UPDATE_HISTORY
*&---------------------------------------------------------------------*
*&      Form  GET_NOROLL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
*&---------------------------------------------------------------------*
*&      Form  GET_NOROLL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_U_CHANGE_MATNR  text
*      -->P_U_CHANGE_WERKS  text
*      -->P_U_CHANGE_CHARG  text
*----------------------------------------------------------------------*
FORM GET_NOROLL  USING    P_MATNR
                          P_WERKS
                          P_BATCHA
                          P_LGORT
                CHANGING P_ROLL.
  DATA : PRO TYPE C LENGTH 30,
         COD TYPE C LENGTH 30,
         MON TYPE C LENGTH 30,
         SEQ TYPE C LENGTH 30,
         GRA TYPE C LENGTH 30,
         DER TYPE C LENGTH 30,
         POS TYPE C LENGTH 30,
         VES TYPE C LENGTH 30,
         ONS TYPE C LENGTH 30.
  CLEAR TBATCH.
  REFRESH TBATCH.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = P_MATNR
      CHARG              = P_BATCHA
      WERKS              = P_WERKS
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = TBATCH
    EXCEPTIONS
      NO_MATERIAL        = 1
      NO_BATCH           = 2
      NO_PLANT           = 3
      MATERIAL_NOT_FOUND = 4
      PLANT_NOT_FOUND    = 5
      NO_AUTHORITY       = 6
      BATCH_NOT_EXIST    = 7
      LOCK_ON_BATCH      = 8
      OTHERS             = 9.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZPRODLINE'.
  IF SY-SUBRC EQ 0.
    SELECT SINGLE CAWN~ATWRT INTO PRO
      FROM CAWN
      JOIN CAWNT ON CAWNT~ATZHL = CAWN~ATZHL AND CAWNT~ATINN = CAWN~ATINN
      WHERE CAWNT~ATWTB = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZCODE'.
  IF SY-SUBRC EQ 0.
    SELECT SINGLE CAWN~ATWRT INTO COD
      FROM CAWN
      JOIN CAWNT ON CAWNT~ATZHL = CAWN~ATZHL AND CAWNT~ATINN = CAWN~ATINN
      WHERE CAWNT~ATWTB = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZMONTHYEAR'.
  IF SY-SUBRC EQ 0.
    MON = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZSEQUENCENBR'.
  IF SY-SUBRC EQ 0.
    SEQ = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZGRADE'.
  IF SY-SUBRC EQ 0.
    SELECT SINGLE CAWN~ATWRT INTO GRA
      FROM CAWN
      JOIN CAWNT ON CAWNT~ATZHL = CAWN~ATZHL AND CAWNT~ATINN = CAWN~ATINN
      WHERE CAWNT~ATWTB = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZDERIVATIVEMS'.
  IF SY-SUBRC EQ 0.
    DER = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZPOSITIONMS'.
  IF SY-SUBRC EQ 0.
    POS = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZDERIVATIVESS'.
  IF SY-SUBRC EQ 0.
    VES = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZPOSITIONSS'.
  IF SY-SUBRC EQ 0.
    ONS = TBATCH-ATWTB.
  ENDIF.
  NOROLL-MATNR = P_MATNR.
  NOROLL-WERKS = P_WERKS.
  NOROLL-LGORT = P_LGORT.
  NOROLL-BATCHA = P_BATCHA.
  CONCATENATE PRO COD MON SEQ GRA DER POS VES ONS INTO NOROLL-ROLL SEPARATED BY SPACE.

  PERFORM VB_GD_TAB USING P_MATNR P_BATCHA P_WERKS.
  DELETE ZCHAR WHERE CHARACT = 'ZZNOMORROLL'.
  ZCHAR-CHARACT = 'ZZNOMORROLL'.
  MOVE NOROLL-ROLL TO ZCHAR-VALUE_CHAR.
  CONDENSE ZCHAR-VALUE_CHAR.
  APPEND ZCHAR.
  PERFORM CHG_CHAR USING P_MATNR P_BATCHA P_WERKS.

  P_ROLL = NOROLL-ROLL.
  REPORT-ZTEX = 'Transaksi Berhasil!'.
  APPEND REPORT.
  CONCATENATE 'Nomor batch yang terbentuk adalah' TCHARG 'dengan nomor roll :' NOROLL-ROLL INTO REPORT-ZTEX SEPARATED BY SPACE.
  APPEND NOROLL.
  APPEND REPORT.
  REPORT-ZTEX = MSG1.
  APPEND REPORT.
  REPORT-ZTEX = MSG2.
  APPEND REPORT.
  CLEAR : REPORT,NOROLL,PRO, COD, MON, SEQ, GRA, DER, POS, VES, ONS.

ENDFORM.                    " GET_NOROLL
*&---------------------------------------------------------------------*
*&      Form  CSRAP
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM CSRAP .
  DATA : DDATE TYPE C LENGTH 8,
         MSG TYPE STRING.
  CLEAR: DDATE.
  CONCATENATE SY-DATUM+6(2) SY-DATUM+4(2) SY-DATUM(4) INTO DDATE.
  OPT-DISMODE  = 'N'.
  OPT-UPDMODE  = 'S'.
  OPT-RACOMMIT = 'X'.
  OPT-DEFSIZE  = 'X'.
  CLEAR :  IT_BDCDATA[], IT_BDCMSGCOLL[].
  REFRESH : IT_BDCMSGCOLL[], IT_BDCDATA[].
  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0100'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RAD1'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=GO'.
  PERFORM BDC_FIELD       USING 'RAD1'
                                'X'.

  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0110'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=EXE'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'P_BATCH-LOW'.
  PERFORM BDC_FIELD       USING 'P_PLANT-LOW'
                                U_CHANGE-WERKS."ZWERKS.
  PERFORM BDC_FIELD       USING 'P_BATCH-LOW'
                                TCHARG."ZCHARG.
*  PERFORM BDC_FIELD       USING 'P_DATE'
*                                DDATE.
  PERFORM BDC_FIELD       USING 'P_NIK'
                                U_CHANGE-AUTHOR."ZNIK.
  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0110'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'WADATA-MATNR(01)'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=CREATE'.
  PERFORM BDC_FIELD       USING 'WADATA-SLOCGR(01)'
                                U_CHANGE-RSLOC."ZLGORT.
  PERFORM BDC_FIELD       USING 'WADATA-MARK(01)'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0110'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=POSTING'.
  PERFORM BDC_DYNPRO      USING 'SAPLSPO1' '0500'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=OPT1'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0110'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=TECO'.
  PERFORM BDC_DYNPRO      USING 'SAPLSPO1' '0500'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=OPT1'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_PO_RAW_RECYCLE' '0110'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=EXIT'.
  CALL TRANSACTION 'ZPP019' USING IT_BDCDATA
                                   OPTIONS FROM OPT
                                   MESSAGES INTO IT_BDCMSGCOLL.

  IF SY-SUBRC EQ 0.
    COMMIT WORK AND WAIT.
    REFRESH : IT_MSEG, DEL_MSEG.
    SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG
    FROM MSEG
    JOIN AUFK ON AUFK~AUFNR = MSEG~AUFNR
      WHERE MSEG~CHARG = TCHARG
      AND MSEG~BWART IN ('261', '262' )
      AND AUFK~AUART IN ('ZRR1', 'ZRR2').
    REFRESH DEL_MSEG.
    DEL_MSEG[] = IT_MSEG[].
    LOOP AT DEL_MSEG WHERE SMBLN IS NOT INITIAL.
      DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-SMBLN.
      DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-MBLNR.
    ENDLOOP.
    READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
    CLEAR MSG2.
    CONCATENATE 'PO Scrap yang terbentuk adalah  ' WA_MSEG-AUFNR INTO MSG2 SEPARATED BY SPACE.
    IF WA_MSEG-AUFNR IS NOT INITIAL.
      U_CHANGE-EXLENG = '0'.
    ENDIF.

*    LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
    U_CHANGE-STATUSKUPAS = 'Sukses'.
    U_CHANGE-POKUPAS = WA_MSEG-AUFNR.

*      MODIFY U_CHANGE TRANSPORTING STATUSKUPAS POKUPAS WHERE BATCHA EQ U_CHANGE-BATCHA.
*    ENDLOOP.
  ELSEIF SY-SUBRC EQ 1001.
    READ TABLE IT_BDCMSGCOLL WITH KEY MSGTYP = 'I'.
    IF SY-SUBRC EQ 0.
      PERFORM VB_GD_TAB USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.

      DELETE ZCHAR WHERE CHARACT = 'ZZGRADE'.
      DELETE ZCHAR WHERE CHARACT = 'ZZCRITERIA'.

      ZCHAR-CHARACT = 'ZZGRADE'.
      MOVE U_CHANGE-GRADEA TO ZCHAR-VALUE_CHAR.
      CONDENSE ZCHAR-VALUE_CHAR.
      APPEND ZCHAR.
      ZCHAR-CHARACT = 'ZZCRITERIA'.
      MOVE U_CHANGE-CRITA TO ZCHAR-VALUE_CHAR.
      CONDENSE ZCHAR-VALUE_CHAR.
      APPEND ZCHAR.
      PERFORM CHG_CHAR USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.

      PERFORM CANCELZPP006 USING U_CHANGE-BATCHA.
      PERFORM CANCELZPP006 USING U_CHANGE-NCHARG.
      CLEAR DSTATUS.
      DSTATUS = 'E'.
      REFRESH REPORT.
      REPORT-ZTEX = 'Transaksi gagal silahkan cek transaksi Anda!'.
      APPEND REPORT.
      CLEAR: REPORT.

      CALL FUNCTION 'MESSAGE_TEXT_BUILD'
        EXPORTING
          MSGID               = IT_BDCMSGCOLL-MSGID
          MSGNR               = IT_BDCMSGCOLL-MSGNR
          MSGV1               = IT_BDCMSGCOLL-MSGV1
          MSGV2               = IT_BDCMSGCOLL-MSGV2
          MSGV3               = IT_BDCMSGCOLL-MSGV3
          MSGV4               = IT_BDCMSGCOLL-MSGV4
        IMPORTING
          MESSAGE_TEXT_OUTPUT = MSG.
*      LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
      U_CHANGE-STATUSKUPAS = 'Error'.
      U_CHANGE-LOGKUPAS = MSG.

*        MODIFY U_CHANGE TRANSPORTING STATUSKUPAS LOGKUPAS WHERE BATCHA EQ U_CHANGE-BATCHA.
*      ENDLOOP.
    ELSE.
      REFRESH : IT_MSEG, DEL_MSEG.
      SELECT * INTO CORRESPONDING FIELDS OF TABLE IT_MSEG
      FROM MSEG
      JOIN AUFK ON AUFK~AUFNR = MSEG~AUFNR
      WHERE MSEG~CHARG = TCHARG
      AND MSEG~BWART IN ('261', '262' )
      AND AUFK~AUART IN ('ZRR1', 'ZRR2').
      REFRESH DEL_MSEG.
      DEL_MSEG[] = IT_MSEG[].
      LOOP AT DEL_MSEG WHERE SMBLN IS NOT INITIAL.
        DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-SMBLN.
        DELETE IT_MSEG WHERE MBLNR = DEL_MSEG-MBLNR.
      ENDLOOP.
      READ TABLE IT_MSEG INTO WA_MSEG INDEX 1.
      CLEAR MSG2.
      CONCATENATE 'PO Scrap yang terbentuk adalah  ' WA_MSEG-AUFNR INTO MSG2 SEPARATED BY SPACE.

*      LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
      U_CHANGE-STATUSKUPAS = 'Sukses'.
      U_CHANGE-POKUPAS = WA_MSEG-AUFNR.

*        MODIFY U_CHANGE TRANSPORTING STATUSKUPAS POKUPAS WHERE BATCHA EQ U_CHANGE-BATCHA.
*      ENDLOOP.
    ENDIF.
  ELSE.
    PERFORM VB_GD_TAB USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.

    DELETE ZCHAR WHERE CHARACT = 'ZZGRADE'.
    DELETE ZCHAR WHERE CHARACT = 'ZZCRITERIA'.

    ZCHAR-CHARACT = 'ZZGRADE'.
    MOVE U_CHANGE-GRADEA TO ZCHAR-VALUE_CHAR.
    CONDENSE ZCHAR-VALUE_CHAR.
    APPEND ZCHAR.
    ZCHAR-CHARACT = 'ZZCRITERIA'.
    MOVE U_CHANGE-CRITA TO ZCHAR-VALUE_CHAR.
    CONDENSE ZCHAR-VALUE_CHAR.
    APPEND ZCHAR.
    PERFORM CHG_CHAR USING U_CHANGE-MATNR TCHARG U_CHANGE-WERKS.

    PERFORM CANCELZPP006 USING U_CHANGE-BATCHA.
    PERFORM CANCELZPP006 USING U_CHANGE-NCHARG.
    CLEAR DSTATUS.
    DSTATUS = 'E'.
    REFRESH REPORT.
    REPORT-ZTEX = 'Transaksi gagal silahkan cek transaksi Anda!'.
    APPEND REPORT.
    CLEAR: REPORT.

    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
      EXPORTING
        MSGID               = IT_BDCMSGCOLL-MSGID
        MSGNR               = IT_BDCMSGCOLL-MSGNR
        MSGV1               = IT_BDCMSGCOLL-MSGV1
        MSGV2               = IT_BDCMSGCOLL-MSGV2
        MSGV3               = IT_BDCMSGCOLL-MSGV3
        MSGV4               = IT_BDCMSGCOLL-MSGV4
      IMPORTING
        MESSAGE_TEXT_OUTPUT = MSG.
    LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
      U_CHANGE-STATUSKUPAS = 'Error'.
      U_CHANGE-LOGKUPAS = MSG.

      MODIFY U_CHANGE TRANSPORTING STATUSKUPAS LOGKUPAS WHERE BATCHA EQ U_CHANGE-BATCHA.
    ENDLOOP.

  ENDIF.


ENDFORM.                    " CSRAP
*&---------------------------------------------------------------------*
*&      Module  STATUS_0400  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*

*&---------------------------------------------------------------------*
*&      Module  WRITE  OUTPUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
MODULE WRITE OUTPUT.
*  LEAVE TO LIST-PROCESSING.
  SORT NOROLL BY ROLL ASCENDING.
  LOOP AT NOROLL.
    WRITE:/ 'No ROll yang terbentuk adalah : '.
    WRITE: NOROLL-ROLL.
  ENDLOOP.
ENDMODULE.                 " WRITE  OUTPUT
*&---------------------------------------------------------------------*
*&      Form  VB_GD_TAB
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_U_CHANGE_MATNR  text
*      -->P_U_CHANGE_BATCHA  text
*      -->P_U_CHANGE_WERKS  text
*----------------------------------------------------------------------*
FORM VB_GD_TAB  USING    ZMAT
                         ZBATCH
                         ZPLANT.
  CLEAR : ZCLBATCH,ZCHAR. REFRESH : ZCLBATCH,ZCHAR.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = ZMAT
      CHARG              = ZBATCH
      WERKS              = ZPLANT
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = ZCLBATCH.

  LOOP AT ZCLBATCH.
    IF ZCLBATCH-ATNAM EQ 'ZZLABEL'.
      MOVE ZCLBATCH-ATNAM TO ZCHAR-CHARACT.
      CONDENSE ZCHAR-CHARACT.
      CLEAR ATINN.
      PERFORM ATNAM USING ZCLBATCH-ATNAM CHANGING ATINN.
      SELECT SINGLE CAWN~ATWRT INTO ZCHAR-VALUE_CHAR
            FROM CAWN
            JOIN CAWNT ON  CAWNT~ATINN = CAWN~ATINN
            AND CAWNT~ATZHL = CAWN~ATZHL
            WHERE CAWNT~ATWTB = ZCLBATCH-ATWTB
            AND CAWN~ATINN = ATINN.
*      MOVE ZCLBATCH-ATWTB TO ZCHAR-VALUE_CHAR.
      CONDENSE ZCHAR-VALUE_CHAR.
      APPEND ZCHAR.
    ELSE.
      MOVE ZCLBATCH-ATNAM TO ZCHAR-CHARACT.
      CONDENSE ZCHAR-CHARACT.
      MOVE ZCLBATCH-ATWTB TO ZCHAR-VALUE_CHAR.
      CONDENSE ZCHAR-VALUE_CHAR.
      APPEND ZCHAR.
    ENDIF.
  ENDLOOP.
ENDFORM.                    " VB_GD_TAB
*&---------------------------------------------------------------------*
*&      Form  CHG_CHAR
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_ZZMSEG_MATNR  text
*      -->P_ZZMSEG_WERKS  text
*      -->P_ZZMSEG_CHARG  text
*----------------------------------------------------------------------*
FORM CHG_CHAR  USING    PDMAT
                        PDCHARG
                        PDWERKS.

  DATA :DCLASS LIKE KLAH-CLASS,
        DKLART LIKE KLAH-KLART,
        DOBTAB LIKE TCLT-OBTAB,
        DOBJKY LIKE BAPI1003_KEY-OBJECT,
        DSTAT LIKE BAPI1003_KEY-STATUS.
  DATA : DMAT LIKE MCHA-MATNR,
       DCHARG LIKE MCHA-CHARG,
       DWERKS LIKE MCHA-WERKS.

  DATA : ZOBJKYTBL LIKE STANDARD TABLE OF BAPI1003_OBJECT_KEYS WITH HEADER LINE,
       ZNUM LIKE STANDARD TABLE OF BAPI1003_ALLOC_VALUES_NUM WITH HEADER LINE,
       ZCURR LIKE STANDARD TABLE OF BAPI1003_ALLOC_VALUES_CURR WITH HEADER LINE.
  CLEAR : ZBRETURN. REFRESH ZBRETURN.

  CALL FUNCTION 'DEQUEUE_ALL'
    EXPORTING
      _SYNCHRON = 'X'.
  MOVE PDMAT TO DMAT.
  MOVE PDCHARG TO DCHARG.
  MOVE PDWERKS TO DWERKS.

  CALL FUNCTION 'QMSP_MATERIAL_BATCH_CLASS_READ'
    EXPORTING
      I_MATNR      = DMAT
      I_CHARG      = DCHARG
      I_WERKS      = DWERKS
      I_MARA_LEVEL = 'X'
    IMPORTING
      E_CLASS      = DCLASS
      E_KLART      = DKLART
      E_OBTAB      = DOBTAB
      E_OBJEC      = DOBJKY.

  CALL FUNCTION 'DEQUEUE_ALL'
    EXPORTING
      _SYNCHRON = 'X'.
  CALL FUNCTION 'BAPI_OBJCL_CHANGE'
    EXPORTING
      OBJECTKEY          = DOBJKY "C 50
      OBJECTTABLE        = DOBTAB "C 30
      CLASSNUM           = DCLASS "C 18
      CLASSTYPE          = DKLART "C 3
    IMPORTING
      CLASSIF_STATUS     = DSTAT
    TABLES
      ALLOCVALUESNUMNEW  = ZNUM
      ALLOCVALUESCHARNEW = ZCHAR
      ALLOCVALUESCURRNEW = ZCURR
      RETURN             = ZBRETURN.
  PERFORM CHK_ER USING '' 'ZBRETURN' CHANGING DSTATUS.
  CHECK DSTATUS NE 'E'.
  PERFORM BAPI_COMMIT.
ENDFORM.                    " CHG_CHAR
*&---------------------------------------------------------------------*
*&      Form  CHK_ER
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_4663   text
*      -->P_4664   text
*      <--P_DSTATUS  text
*----------------------------------------------------------------------*
FORM CHK_ER USING ZMSG ZTBL CHANGING ZSTATUS.
  DATA : DMSG TYPE C LENGTH 100.
  MOVE ZMSG TO DMSG.
  IF ZTBL = 'ZBRETURN'.
    READ TABLE ZBRETURN WITH KEY TYPE = 'E'.
    IF SY-SUBRC = 0.
      LOOP AT ZBRETURN WHERE TYPE = 'E'.
        LSEQ = LSEQ + 1.
        LMSG-MSGID = '00'.
        LMSG-MSGTY = 'E'.
        LMSG-MSGNO = '1'.
        MOVE ZBRETURN-MESSAGE TO LMSG-MSGV1.
        MOVE ZBRETURN-MESSAGE+50 TO LMSG-MSGV2.
        MOVE LSEQ TO LMSG-LINENO.
        APPEND LMSG.
      ENDLOOP.
      ZSTATUS = 'E'.
    ELSE.
      IF ZMSG IS NOT INITIAL.
        LSEQ = LSEQ + 1.
        LMSG-MSGID = '00'.
        LMSG-MSGTY = 'S'.
        LMSG-MSGNO = '1'.
        MOVE DMSG TO LMSG-MSGV1.
        MOVE DMSG+50 TO LMSG-MSGV2.
        MOVE LSEQ TO LMSG-LINENO.
        APPEND LMSG.
      ENDIF.
      ZSTATUS = 'S'.
    ENDIF.
  ENDIF.
ENDFORM.                    " CHK_ER
*&---------------------------------------------------------------------*
*&      Form  BAPI_COMMIT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM BAPI_COMMIT .
  CALL FUNCTION 'BAPI_TRANSACTION_COMMIT'
    EXPORTING
      WAIT = 'X'.
ENDFORM.                    " BAPI_COMMIT
*&---------------------------------------------------------------------*
*&      Form  ATNAM
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->P_TBATCH_ATNAM  text
*      <--P_ATINN  text
*----------------------------------------------------------------------*
FORM ATNAM  USING    P_TBATCH_ATNAM
            CHANGING P_ATINN.
  CALL FUNCTION 'CONVERSION_EXIT_ATINN_INPUT'
    EXPORTING
      INPUT  = P_TBATCH_ATNAM
    IMPORTING
      OUTPUT = P_ATINN.

ENDFORM.                    " ATNAM
*&---------------------------------------------------------------------*
*&      Form  CHANGE
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM CHANGE .
  DATA: TXT TYPE C LENGTH 40,
        MSGEXLENG2 TYPE STRING,
        CHECKEXLENG LIKE DD01V-DATATYPE,
        FLAGCHECKEXLENG TYPE C.
  CLEAR : U_CHANGE,NOROLL, JLH,REPORT,TXT,U_HU,IT_HU.
  REFRESH :U_CHANGE,NOROLL,REPORT,U_HU,IT_HU.



  U_CHANGE[] = IT_CHANGE[].
  DELETE U_CHANGE WHERE CHK NE 'X'.
  LOOP AT U_CHANGE WHERE CRITB NE 'S' AND RSLOC IS NOT INITIAL.
    CLEAR U_CHANGE-RSLOC.
    MODIFY U_CHANGE.
  ENDLOOP.
  LOOP AT U_CHANGE.
    CLEAR : INSP,NOREF.
    READ TABLE IT_GRADE WITH KEY VTVALUE = U_CHANGE-GRADEB.
    IF SY-SUBRC NE 0.
      JLH = 2.
      MESSAGE 'Grade tidak ditemukan!' TYPE 'I'.
      EXIT.
    ENDIF.
    SELECT SINGLE HROID ARBPL
      INTO (HROID, ARBPL)
      FROM CRHD
      WHERE ARBPL = 'QA-CRD' AND
            OBJTY = 'A'.

    SELECT OBJID
      INTO CORRESPONDING FIELDS OF TABLE IT_NIK
      FROM HRP1001
      WHERE SOBID = HROID AND
            OTYPE = 'P'.
    CLEAR MESG.
    READ TABLE IT_NIK WITH KEY OBJID = U_CHANGE-AUTHOR.
    IF SY-SUBRC NE 0.
      JLH = 2.
      CONCATENATE U_CHANGE-AUTHOR 'NIK tidak ditemukan pada W.cntr' ARBPL '!' INTO MESG SEPARATED BY SPACE.
      MESSAGE  MESG TYPE 'I'.
      CLEAR: U_CHANGE-AUTHOR,U_CHANGE-WC.
      EXIT.
    ENDIF.
  ENDLOOP.
  IF JLH EQ 2.
    EXIT.
  ENDIF.
  CLEAR JLH.

***      validasi HU
  U_HU[] = U_CHANGE[].
  SORT U_HU BY  EXIDV.
  DELETE ADJACENT DUPLICATES FROM U_HU COMPARING EXIDV.
  LOOP AT U_HU.
    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        INPUT  = U_HU-EXIDV
      IMPORTING
        OUTPUT = U_HU-EXIDV.

    SELECT VEPO~VENUM VEPO~UNVEL VEPO~CHARG INTO (IT_HU-VENUM,IT_HU-UNVEL,IT_HU-CHARG)
      FROM VEPO
      JOIN VEKP ON VEKP~VENUM = VEPO~VENUM
      WHERE VEKP~EXIDV = U_HU-EXIDV.
      IT_HU-EXIDV = U_HU-EXIDV.
      APPEND IT_HU.
    ENDSELECT.
    MODIFY U_HU.
  ENDLOOP.
  LOOP AT IT_HU.
    INDEX = SY-TABIX.
    IF IT_HU-UNVEL IS NOT INITIAL.
      SELECT VEPO~VENUM VEPO~UNVEL VEPO~CHARG  INTO (IT_HU-VENUM,IT_HU-UNVEL,IT_HU-CHARG)
         FROM VEPO
         WHERE VEPO~VENUM = IT_HU-UNVEL.
        IT_HU-EXIDV = IT_HU-EXIDV.
        IT_HU-OCHARG = IT_HU-CHARG.
        APPEND IT_HU.
      ENDSELECT.
      DELETE IT_HU INDEX INDEX.
    ENDIF.
  ENDLOOP.
  LOOP AT U_HU.
    LOOP AT IT_HU WHERE EXIDV = U_HU-EXIDV.
      CALL FUNCTION 'CONVERSION_EXIT_ALPHA_OUTPUT'
        EXPORTING
          INPUT  = U_HU-EXIDV
        IMPORTING
          OUTPUT = U_HU-EXIDV.
      READ TABLE U_CHANGE WITH KEY EXIDV = U_HU-EXIDV BATCHA = IT_HU-CHARG.
      IF SY-SUBRC NE 0.
        JLH = 2.
        CONCATENATE 'Batch tidak lengkap untuk HU' U_HU-EXIDV INTO TXT SEPARATED BY SPACE.
        MESSAGE I016(PN) WITH TXT.
        EXIT.
      ENDIF.
    ENDLOOP.
  ENDLOOP.
  IF JLH EQ 2.
    EXIT.
  ENDIF.
  CLEAR : HU, BA, CRI,JLH.
  SORT U_CHANGE BY EXIDV BATCHA CRITB ASCENDING.
  READ TABLE U_CHANGE INDEX 1.
  LOOP AT U_CHANGE.
    IF U_CHANGE-EXIDV IS NOT INITIAL.
      IF HU = U_CHANGE-EXIDV  AND CRI NE U_CHANGE-CRITB."AND BA = U_CHANGE-BATCHA
        JLH = 2.
        MESSAGE 'Criteria Grade Baru harus sama dalam satu HU' TYPE 'I'. "U_CHANGE-RSLOC
        EXIT.
      ENDIF.
      IF ( U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2' ) AND ( U_CHANGE-CRITB EQ 'B' OR U_CHANGE-CRITB EQ 'R' OR U_CHANGE-CRITB EQ 'S' ) .
        JLH = 2.
        MESSAGE 'Batch untuk Criteria Grade B atau R atau S tidak boleh terikat HU.' TYPE 'I'. "U_CHANGE-RSLOC
        EXIT.
      ENDIF.
      IF U_CHANGE-CRITA EQ 'R' AND ( U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2' OR U_CHANGE-CRITB EQ 'S' OR U_CHANGE-CRITB EQ 'B').
        JLH = 2.
        MESSAGE 'Criteria Grade Baru harus diunpack HU.' TYPE 'I'. "U_CHANGE-RSLOC
        EXIT.
      ENDIF.
      IF U_CHANGE-CRITA EQ 'B' AND  U_CHANGE-CRITB NE 'B'.
        JLH = 2.
        MESSAGE 'Criteria Grade baru harus diunpack HU.' TYPE 'I'. "U_CHANGE-RSLOC
        EXIT.
      ENDIF.
      HU = U_CHANGE-EXIDV.
      BA = U_CHANGE-BATCHA.
      CRI = U_CHANGE-CRITB.
    ENDIF.
  ENDLOOP.
  IF JLH EQ 2.
    EXIT.
  ENDIF.

  LOOP AT U_CHANGE WHERE CRITB EQ 'S'.
    CLEAR: ITHELP,JLH.
    REFRESH ITHELP.

    SELECT DISTINCT WERKS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
      FROM MARD
      WHERE MARD~WERKS = U_CHANGE-WERKS.
    READ TABLE ITHELP WITH KEY LGORT = U_CHANGE-RSLOC.
    IF SY-SUBRC NE 0.
      JLH = 1.
      MESSAGE 'Sloc Raw Recycle tidak sesuai!' TYPE 'I'. "U_CHANGE-RSLOC
      EXIT.
    ENDIF.
  ENDLOOP.
  IF JLH EQ 1.
    EXIT.
  ENDIF.
  LOOP AT U_CHANGE.
    CALL FUNCTION 'NUMERIC_CHECK'
      EXPORTING
        STRING_IN = U_CHANGE-EXLENG
      IMPORTING
        HTYPE     = CHECKEXLENG.

    IF CHECKEXLENG EQ 'CHAR'.
      CONCATENATE 'Batch' U_CHANGE-BATCHA 'Extra Length Salah!!' INTO MSGEXLENG2 SEPARATED BY SPACE.
      MESSAGE MSGEXLENG2 TYPE 'I'.
      FLAGCHECKEXLENG = '1'.
      EXIT.
    ENDIF.

  ENDLOOP.

  LOOP AT U_CHANGE.
    IF ( U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2' ) AND ( U_CHANGE-EXLENG IS INITIAL OR U_CHANGE-EXLENG EQ '0' ).
      CONCATENATE 'Batch' U_CHANGE-BATCHA 'Tidak Memiliki Extra Length' INTO MSGEXLENG2 SEPARATED BY SPACE.
      MESSAGE MSGEXLENG2 TYPE 'I'.
      FLAGCHECKEXLENG = '2'.
      EXIT.
    ENDIF.
    IF ( U_CHANGE-CRITA EQ 'B'  OR U_CHANGE-CRITA EQ 'R' ) AND ( U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2' ) AND ( U_CHANGE-EXLENG IS INITIAL OR U_CHANGE-EXLENG EQ '0' ).
      CONCATENATE 'Batch' U_CHANGE-BATCHA 'Tidak Memiliki Extra Length' INTO MSGEXLENG2 SEPARATED BY SPACE.
      MESSAGE MSGEXLENG2 TYPE 'I'.
      FLAGCHECKEXLENG = '2'.
      EXIT.
    ENDIF.
  ENDLOOP.

  CLEAR: JLH.
  JLH = LINES( U_CHANGE ).
  IF JLH IS INITIAL.
    MESSAGE 'Harap memilih data!' TYPE 'I'.
  ELSE.
    IF FLAGCHECKEXLENG EQ '1'.

    ELSE.
      IF FLAGCHECKEXLENG EQ '2'.

      ELSE.
        READ TABLE U_CHANGE WITH KEY GRADEB = ''.
        IF SY-SUBRC EQ 0.
          MESSAGE 'Harap Mengisi Grade Baru!' TYPE 'I'.
        ELSE.
          READ TABLE U_CHANGE WITH KEY NMEMO = ''.
          IF SY-SUBRC EQ 0.
            MESSAGE 'Harap Mengisi No. Memo!' TYPE 'I'.
          ELSE.
            READ TABLE U_CHANGE WITH KEY AUTHOR = ''.
            IF SY-SUBRC EQ 0.
              MESSAGE 'Harap Mengisi Authorizer!' TYPE 'I'.
            ELSE.
              READ TABLE U_CHANGE WITH KEY CRITB = 'S' RSLOC = ''.
              IF SY-SUBRC EQ 0.
                MESSAGE 'Harap Mengisi Sloc Raw Material!' TYPE 'I'.


              ELSE.
*            PERFORM GET_EXLENGTH.
                CALL SCREEN 300 STARTING AT 10 4 ENDING AT 90 16.
                IF FLAG EQ 'Y'.
                  PERFORM CHANGE_GRADE.
                  DATA: L_FCODE TYPE TABLE OF SY-UCOMM.
                  APPEND 'CHANGE' TO L_FCODE.
                  APPEND 'BACK' TO L_FCODE.
                  APPEND 'SELALL' TO L_FCODE.
                  APPEND 'DESALL' TO L_FCODE.
                  APPEND 'PRINT' TO L_FCODE.
                  SET PF-STATUS 'MAIN100' EXCLUDING L_FCODE.
                  LEAVE TO LIST-PROCESSING.
                  PERFORM DISPLAY_FINAL.
*              LOOP AT REPORT.
*                WRITE:/ REPORT-ZTEX.
*              ENDLOOP.
                ENDIF.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDIF.
ENDFORM.                    " CHANGE
*&---------------------------------------------------------------------*
*&      Form  DISPLAY
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM DISPLAY .
  D_REPID = SY-REPID.
  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      I_CALLBACK_PROGRAM       = D_REPID
      I_CALLBACK_USER_COMMAND  = 'USER_COMMAND'
      I_CALLBACK_PF_STATUS_SET = 'F_GUI_STATUS'
      IS_LAYOUT                = WA_LAYOUT
      IT_FIELDCAT              = T_FIELDCAT[]
      IT_EVENTS                = T_EVENTS[]
      IT_EVENT_EXIT            = T_EVENT_EXIT[]
      I_DEFAULT                = 'X'
      I_SAVE                   = 'A'
      IS_VARIANT               = WA_VARIANTE
      IS_PRINT                 = T_PRINT
      IT_SORT                  = T_SORT[]
      IT_EXCLUDING             = T_EXCLUDING[]
      I_BYPASSING_BUFFER       = 'X'
    TABLES
      T_OUTTAB                 = IZBATCHISTORY
    EXCEPTIONS
      PROGRAM_ERROR            = 1
      OTHERS                   = 2.
ENDFORM.                    " DISPLAY
*&---------------------------------------------------------------------*
*&      Form  F_GUI_STATUS
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->FT_EXTAB   text
*----------------------------------------------------------------------*
FORM F_GUI_STATUS USING FT_EXTAB TYPE SLIS_T_EXTAB.
  DATA: LT_FCODE TYPE TABLE OF SY-UCOMM.
  APPEND 'CHANGE' TO LT_FCODE.
  APPEND 'EXIT' TO LT_FCODE.
  SET PF-STATUS 'MAIN100' EXCLUDING LT_FCODE.
ENDFORM.                    "F_GUI_STATUS
*&---------------------------------------------------------------------*
*&      Form  USER_COMMAND
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->R_UCOMM      text
*      -->RS_SELFIELD  text
*----------------------------------------------------------------------*
FORM USER_COMMAND USING R_UCOMM LIKE SY-UCOMM
                  RS_SELFIELD TYPE SLIS_SELFIELD.
  RANGES: PHU FOR VEKP-EXIDV.
  DATA: P_COUNT TYPE I.
  CLEAR P_COUNT.


  CALL FUNCTION 'GET_GLOBALS_FROM_SLVC_FULLSCR'
    IMPORTING
      E_GRID = LS_REF1.

  CALL METHOD LS_REF1->CHECK_CHANGED_DATA .
  CASE R_UCOMM.
    WHEN 'BACK'.
      LEAVE TO SCREEN 0.
    WHEN '&F03'.
      LEAVE TO SCREEN 0.
    WHEN 'SELALL'.
      LOOP AT IZBATCHISTORY  WHERE CHK NE 'X'.
        IZBATCHISTORY-CHK = 'X'.
        MODIFY IZBATCHISTORY.
      ENDLOOP.
      CALL METHOD LS_REF1->REFRESH_TABLE_DISPLAY .
    WHEN 'DESALL'.
      LOOP AT IZBATCHISTORY WHERE CHK NE ''.
        IZBATCHISTORY-CHK = ''.
        MODIFY IZBATCHISTORY.
      ENDLOOP.
      CALL METHOD LS_REF1->REFRESH_TABLE_DISPLAY .
    WHEN 'PRINT'.
      REFRESH PHU.
      LOOP AT IZBATCHISTORY WHERE CHK = 'X'.
*        REFRESH PHU.
        PHU-SIGN   = 'I'.
        PHU-OPTION = 'EQ'.
        PHU-LOW = IZBATCHISTORY-CHARG.
        APPEND PHU.
      ENDLOOP.
      SUBMIT ZMMR_LABELROL WITH  P_CHARG IN PHU
*                            WITH V_COPIES = 1
      AND RETURN.
      LOOP AT PHU.
        UPDATE ZBATCHISTORY SET SPRNT = 'X'
        WHERE ZBATCHISTORY~CHARG = PHU-LOW.
      ENDLOOP.
  ENDCASE.
  CALL METHOD LS_REF1->REFRESH_TABLE_DISPLAY .
  CLEAR R_UCOMM.
ENDFORM. "USER_COMMAND
*&---------------------------------------------------------------------*
*&      Form  LAYOUT
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM LAYOUT .
  CLEAR WA_LAYOUT.
  WA_LAYOUT-ZEBRA = 'X'.
  WA_LAYOUT-CELL_MERGE = 'X'.
*  WA_LAYOUT-COLWIDTH_OPTIMIZE = 'X'.
ENDFORM.                    " LAYOUT
*&---------------------------------------------------------------------*
*&      Form  SAVE_OLAP
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM SAVE_OLAP .
** di ubah bagus ya ^^
  EXEC SQL.
    SET CONNECTION :S_CONN
  ENDEXEC.

  EXEC SQL.
    CONNECT TO :S_CONN
  ENDEXEC.

  TRY .
      EXEC SQL.
        DELETE FROM XZQM016
      ENDEXEC.

      EXEC SQL.
        COMMIT WORK
      ENDEXEC.

    CATCH CX_SY_NATIVE_SQL_ERROR.
      MESSAGE `Error in procedure execution delete` TYPE 'I'.
      RETURN.
  ENDTRY.


  TRY .
      LOOP AT IZBATCHISTORY.
        EXEC SQL.
          INSERT INTO XZQM016(COL001,COL002,COL003,COL004,COL005,COL006,COL007,COL008,COL009,COL010,COL011,COL012,COL013,COL014,COL015,
                              COL016,COL017,COL018,COL019,COL020,COL021,COL022,COL023,COL024,COL025)
          VALUES(:IZBATCHISTORY-EXIDV,:IZBATCHISTORY-BUDAT,:IZBATCHISTORY-UZEIT,:IZBATCHISTORY-MATNR,:IZBATCHISTORY-TYPE,:IZBATCHISTORY-LENGHT,:IZBATCHISTORY-WEIGHT
                 ,:IZBATCHISTORY-WIDTH,:IZBATCHISTORY-WERKS,:IZBATCHISTORY-LGORT,:IZBATCHISTORY-NOROLL,:IZBATCHISTORY-CHARG,:IZBATCHISTORY-GRADE,:IZBATCHISTORY-DGRADE
                 ,:IZBATCHISTORY-DCRITA,:IZBATCHISTORY-NOROLL2,:IZBATCHISTORY-GRADE2,:IZBATCHISTORY-DGRADE2,:IZBATCHISTORY-DCRITB,:IZBATCHISTORY-NMEMO,:IZBATCHISTORY-AUTHR
                 ,:IZBATCHISTORY-NOTES,:IZBATCHISTORY-UNAME,:IZBATCHISTORY-RSLOC,:IZBATCHISTORY-SPRNT)
        ENDEXEC.
      ENDLOOP.

      MESSAGE 'Penyimpanan Data ke SQL sukses!!!' TYPE 'I'.

      EXEC SQL.
        COMMIT WORK
      ENDEXEC.

    CATCH CX_SY_NATIVE_SQL_ERROR.
      MESSAGE `Error in procedure execution insert` TYPE 'I'.
      RETURN.
  ENDTRY.
**  -- 3 jan 12
ENDFORM.                    " SAVE_OLAP
*&---------------------------------------------------------------------*
*&      Form  CALL_ZPP006
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM CALL_ZPP006 .
  DATA: MSG TYPE STRING.
*  BREAK-POINT.
  OPT-DISMODE  = 'N'.
  OPT-UPDMODE  = 'A'.
  OPT-RACOMMIT = 'X'.
*  OPT-DEFSIZE  = 'X'.
  CLEAR :  IT_BDCDATA[], IT_BDCMSGCOLL[].
  REFRESH : IT_BDCMSGCOLL[], IT_BDCDATA[].

  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7000'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=BTNGO'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RB_MAINTAIN'.
  PERFORM BDC_FIELD       USING 'RB_MAINTAIN'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=BTNGO'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'SO_NIK-LOW'.
  PERFORM BDC_FIELD       USING 'SO_PLANT-LOW'
                                U_CHANGE-WERKS."'2000'.
  PERFORM BDC_FIELD       USING 'SO_BATCH-LOW'
                                U_CHANGE-BATCHA."'0000003427'.
  PERFORM BDC_FIELD       USING 'SO_NIK-LOW'
                                U_CHANGE-AUTHOR."'19'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=BTN_MGO'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'SO_NIK-LOW'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=POST'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'WA_MAINTAIN-NOMOR(01)'.
  PERFORM BDC_FIELD       USING 'WA_MAINTAIN-EXLENG(01)'
                                U_CHANGE-EXLENG."'100'.
  PERFORM BDC_FIELD       USING 'WA_MAINTAIN-FLAGS(01)'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'SAPMSSY0' '0120'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=&F03'.
  PERFORM BDC_DYNPRO      USING 'SAPLSPO1' '0100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=YES'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '/EBACK'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7000'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '/EBACK'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RB_MAINTAIN'.
  PERFORM BDC_FIELD       USING 'RB_MAINTAIN'
                                'X'.
  CALL TRANSACTION 'ZPP006' USING IT_BDCDATA
                                   OPTIONS FROM OPT
                                   MESSAGES INTO IT_BDCMSGCOLL.

  IF SY-SUBRC EQ 0.
    U_CHANGE-STATUSEXLENG = 'Sukses'.
    U_CHANGE-LOGEXLENG = '-'.

    COMMIT WORK AND WAIT.
  ELSEIF SY-SUBRC EQ 1001.
    READ TABLE IT_BDCMSGCOLL WITH KEY MSGTYP = 'I'.
    IF SY-SUBRC EQ 0.
      CALL FUNCTION 'MESSAGE_TEXT_BUILD'
        EXPORTING
          MSGID               = IT_BDCMSGCOLL-MSGID
          MSGNR               = IT_BDCMSGCOLL-MSGNR
          MSGV1               = IT_BDCMSGCOLL-MSGV1
          MSGV2               = IT_BDCMSGCOLL-MSGV2
          MSGV3               = IT_BDCMSGCOLL-MSGV3
          MSGV4               = IT_BDCMSGCOLL-MSGV4
        IMPORTING
          MESSAGE_TEXT_OUTPUT = MSG.

      U_CHANGE-STATUSEXLENG = 'Error'.
      U_CHANGE-LOGEXLENG = MSG.
    ELSE.
      U_CHANGE-STATUSEXLENG = 'Sukses'.
      U_CHANGE-LOGEXLENG = '-'.

      COMMIT WORK AND WAIT.
    ENDIF.
  ELSE.
    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
      EXPORTING
        MSGID               = IT_BDCMSGCOLL-MSGID
        MSGNR               = IT_BDCMSGCOLL-MSGNR
        MSGV1               = IT_BDCMSGCOLL-MSGV1
        MSGV2               = IT_BDCMSGCOLL-MSGV2
        MSGV3               = IT_BDCMSGCOLL-MSGV3
        MSGV4               = IT_BDCMSGCOLL-MSGV4
      IMPORTING
        MESSAGE_TEXT_OUTPUT = MSG.


    U_CHANGE-STATUSEXLENG = 'Error'.
    U_CHANGE-LOGEXLENG = MSG.



  ENDIF.

*  IF SY-SUBRC EQ 0 OR SY-SUBRC EQ 1001.
*    READ TABLE IT_BDCMSGCOLL WITH KEY MSGTYP = 'I'.
*    IF SY-SUBRC EQ 0.
*      CALL FUNCTION 'MESSAGE_TEXT_BUILD'
*        EXPORTING
*          MSGID               = IT_BDCMSGCOLL-MSGID
*          MSGNR               = IT_BDCMSGCOLL-MSGNR
*          MSGV1               = IT_BDCMSGCOLL-MSGV1
*          MSGV2               = IT_BDCMSGCOLL-MSGV2
*          MSGV3               = IT_BDCMSGCOLL-MSGV3
*          MSGV4               = IT_BDCMSGCOLL-MSGV4
*        IMPORTING
*          MESSAGE_TEXT_OUTPUT = MSG.
*
*      LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
*        U_CHANGE-STATUSEXLENG = 'Error'.
*        U_CHANGE-LOGEXLENG = MSG.
*
*        MODIFY U_CHANGE TRANSPORTING STATUSEXLENG LOGEXLENG WHERE BATCHA EQ U_CHANGE-BATCHA.
*      ENDLOOP.
*
*    ELSE.
*      LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
*        U_CHANGE-STATUSEXLENG = 'Sukses'.
*        U_CHANGE-LOGEXLENG = '-'.
*
*        MODIFY U_CHANGE TRANSPORTING STATUSEXLENG LOGEXLENG WHERE BATCHA EQ U_CHANGE-BATCHA.
*      ENDLOOP.
*      COMMIT WORK AND WAIT.
*    ENDIF.
*  ELSE.
*    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
*      EXPORTING
*        MSGID               = IT_BDCMSGCOLL-MSGID
*        MSGNR               = IT_BDCMSGCOLL-MSGNR
*        MSGV1               = IT_BDCMSGCOLL-MSGV1
*        MSGV2               = IT_BDCMSGCOLL-MSGV2
*        MSGV3               = IT_BDCMSGCOLL-MSGV3
*        MSGV4               = IT_BDCMSGCOLL-MSGV4
*      IMPORTING
*        MESSAGE_TEXT_OUTPUT = MSG.
*
*    LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
*      U_CHANGE-STATUSEXLENG = 'Error'.
*      U_CHANGE-LOGEXLENG = MSG.
*
*      MODIFY U_CHANGE TRANSPORTING STATUSEXLENG LOGEXLENG WHERE BATCHA EQ U_CHANGE-BATCHA.
*    ENDLOOP.
*
*  ENDIF.

ENDFORM.                    " CALL_ZPP006
*&---------------------------------------------------------------------*
*&      Form  GET_EXLENGTH
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM GET_EXLENGTH .

  DATA: EXLENG_LAMA LIKE AUSP-ATWRT. "add by rey (15/11/2017)
  CLEAR: EXLENG_LAMA. "add by rey (15/11/2017)
  CLEAR: IT_SOPOP,EXLENG.
  REFRESH : IT_SOPOP.

  PERFORM GET_EXLENGHT_LAMA USING U_CHANGE-MATNR U_CHANGE-BATCHA U_CHANGE-WERKS CHANGING EXLENG_LAMA. "add by rey (15/11/2017)

  CONDENSE EXLENG_LAMA. "add by rey (15/11/2017)

  IT_SOPOP-TABNAME = 'MCHB'.
  IT_SOPOP-FIELDNAME = 'CHARG'.
  IT_SOPOP-FIELDTEXT  = 'Batch'.
  IT_SOPOP-VALUE = U_CHANGE-BATCHA.
  IT_SOPOP-FIELD_ATTR = '02'.
  APPEND IT_SOPOP.

  CLEAR IT_SOPOP.
  IT_SOPOP-TABNAME = 'ZBATCHISTORY'.
  IT_SOPOP-FIELDNAME = 'NLENGHT'.
  IT_SOPOP-FIELDTEXT  = 'Length(M)'.
  IT_SOPOP-VALUE = EXLENG_LAMA.
  IT_SOPOP-FIELD_ATTR = '02'.
  APPEND IT_SOPOP.


  CLEAR IT_SOPOP.
  IT_SOPOP-TABNAME = 'ZBATCHISTORY'.
  IT_SOPOP-FIELDNAME = 'EXLENG'.
  IT_SOPOP-FIELDTEXT  = 'Extra Length'.
  IT_SOPOP-FIELD_OBL = 'X'.
  APPEND IT_SOPOP.



  CALL FUNCTION 'POPUP_GET_VALUES'
    EXPORTING
      POPUP_TITLE     = 'Input Extra Length '
      START_COLUMN    = '5'
      START_ROW       = '5'
    IMPORTING
      RETURNCODE      = RETURNCODE
    TABLES
      FIELDS          = IT_SOPOP
    EXCEPTIONS
      ERROR_IN_FIELDS = 1.
  IF RETURNCODE EQ 'A'.
    LEAVE SCREEN.
  ELSE.
    READ TABLE IT_SOPOP WITH KEY FIELDNAME = 'EXLENG'.
    IF SY-SUBRC EQ 0.
      CONDENSE IT_SOPOP-VALUE.
      EXLENG = IT_SOPOP-VALUE.
      CONDENSE EXLENG.
    ENDIF.
  ENDIF.
ENDFORM.                    " GET_EXLENGTH
*&---------------------------------------------------------------------*
*&      Form  CANCELZPP006
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*  -->  p1        text
*  <--  p2        text
*----------------------------------------------------------------------*
FORM CANCELZPP006 USING CBATCH.
  DATA:MSG TYPE STRING.

  OPT-DISMODE  = 'N'.
  OPT-UPDMODE  = 'A'.
  OPT-RACOMMIT = 'X'.
*  OPT-DEFSIZE  = 'X'.
  CLEAR :  IT_BDCDATA[], IT_BDCMSGCOLL[].
  REFRESH : IT_BDCMSGCOLL[], IT_BDCDATA[].

  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7000'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=RB_MENU'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RB_CANCEL'.
  PERFORM BDC_FIELD       USING 'RB_MAINTAIN'
                                ''.
  PERFORM BDC_FIELD       USING 'RB_CANCEL'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7000'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=BTNGO'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RB_CANCEL'.
  PERFORM BDC_FIELD       USING 'RB_CANCEL'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7200'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=BTN_CGO'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'S_NIK-LOW'.
  PERFORM BDC_FIELD       USING 'S_BATCH-LOW'
                                CBATCH.
  PERFORM BDC_FIELD       USING 'S_PLANT-LOW'
                                U_CHANGE-WERKS.
  PERFORM BDC_FIELD       USING 'S_POSDT-LOW'
                                '10.01.2013'.
  PERFORM BDC_FIELD       USING 'S_NIK-LOW'
                                U_CHANGE-AUTHOR.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7220'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=CANC'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'IT_DISPLAY-AUFNR(01)'.
  PERFORM BDC_FIELD       USING 'IT_DISPLAY-FLAGS(01)'
                                'X'.
  PERFORM BDC_DYNPRO      USING 'SAPMSSY0' '0120'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=&F03'.
  PERFORM BDC_DYNPRO      USING 'SAPLSPO1' '0100'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '=YES'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7200'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '/EBACK'.
  PERFORM BDC_DYNPRO      USING 'ZPPI_RESLIT_ROLL' '7000'.
  PERFORM BDC_FIELD       USING 'BDC_OKCODE'
                                '/EBACK'.
  PERFORM BDC_FIELD       USING 'BDC_CURSOR'
                                'RB_MAINTAIN'.
  PERFORM BDC_FIELD       USING 'RB_CANCEL'
                                'X'.




  CALL TRANSACTION 'ZPP006' USING IT_BDCDATA
                                   OPTIONS FROM OPT
                                   MESSAGES INTO IT_BDCMSGCOLL.

  IF SY-SUBRC EQ 0.
    U_CHANGE-LOGEXLENGCANCEL = 'Sukses'.

    COMMIT WORK AND WAIT.
  ELSEIF SY-SUBRC EQ 1001.
    READ TABLE IT_BDCMSGCOLL WITH KEY MSGTYP = 'I'.
    IF SY-SUBRC EQ 0.
      CALL FUNCTION 'MESSAGE_TEXT_BUILD'
        EXPORTING
          MSGID               = IT_BDCMSGCOLL-MSGID
          MSGNR               = IT_BDCMSGCOLL-MSGNR
          MSGV1               = IT_BDCMSGCOLL-MSGV1
          MSGV2               = IT_BDCMSGCOLL-MSGV2
          MSGV3               = IT_BDCMSGCOLL-MSGV3
          MSGV4               = IT_BDCMSGCOLL-MSGV4
        IMPORTING
          MESSAGE_TEXT_OUTPUT = MSG.

      U_CHANGE-LOGEXLENGCANCEL = MSG.
    ELSE.
      U_CHANGE-LOGEXLENGCANCEL = 'Sukses'.

      COMMIT WORK AND WAIT.
    ENDIF.
  ELSE.
    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
      EXPORTING
        MSGID               = IT_BDCMSGCOLL-MSGID
        MSGNR               = IT_BDCMSGCOLL-MSGNR
        MSGV1               = IT_BDCMSGCOLL-MSGV1
        MSGV2               = IT_BDCMSGCOLL-MSGV2
        MSGV3               = IT_BDCMSGCOLL-MSGV3
        MSGV4               = IT_BDCMSGCOLL-MSGV4
      IMPORTING
        MESSAGE_TEXT_OUTPUT = MSG.

    U_CHANGE-LOGEXLENGCANCEL = MSG.

  ENDIF.


*  IF SY-SUBRC EQ 0 ."OR SY-SUBRC EQ 1001.
**    LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
*    U_CHANGE-LOGEXLENGCANCEL = 'Sukses'.
*
**      MODIFY U_CHANGE TRANSPORTING LOGEXLENGCANCEL WHERE BATCHA EQ U_CHANGE-BATCHA.
**    ENDLOOP.
*    COMMIT WORK AND WAIT.
*  ELSE.
*    CALL FUNCTION 'MESSAGE_TEXT_BUILD'
*      EXPORTING
*        MSGID               = IT_BDCMSGCOLL-MSGID
*        MSGNR               = IT_BDCMSGCOLL-MSGNR
*        MSGV1               = IT_BDCMSGCOLL-MSGV1
*        MSGV2               = IT_BDCMSGCOLL-MSGV2
*        MSGV3               = IT_BDCMSGCOLL-MSGV3
*        MSGV4               = IT_BDCMSGCOLL-MSGV4
*      IMPORTING
*        MESSAGE_TEXT_OUTPUT = MSG.
*
**    LOOP AT U_CHANGE WHERE BATCHA EQ U_CHANGE-BATCHA.
*    U_CHANGE-LOGEXLENGCANCEL = MSG.
*
**      MODIFY U_CHANGE TRANSPORTING LOGEXLENGCANCEL WHERE BATCHA EQ U_CHANGE-BATCHA.
**    ENDLOOP.
**    DSTATUS = 'E'.
**    REFRESH REPORT.
**    REPORT-ZTEX = 'Transaksi gagal silahkan cek transaksi Anda!'.
**    APPEND REPORT.
**    CLEAR: REPORT.
*  ENDIF.

ENDFORM.                    " CANCELZPP006

*&---------------------------------------------------------------------*
*&      Form  GET_EXLENGHT_LAMA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->MAT          text
*      -->BATCH        text
*      -->PLANT        text
*      -->EXLENG_LAMA  text
*      add by rey (15/11/2017)
*----------------------------------------------------------------------*
FORM GET_EXLENGHT_LAMA USING MAT BATCH PLANT CHANGING EXLENG_LAMA. "add by rey (15/11/2017)

*  DATA:VX_ATNUOM LIKE CABN-ATINN,
*        VX_UOM LIKE AUSP-ATWRT.
*
*SELECT SINGLE ATINN INTO VX_ATNUOM FROM CABN WHERE ATNAM = 'ZZEXLENGTH'.
*
* SELECT SINGLE  AUSP~ATWRT INTO VX_UOM
*    FROM AUSP JOIN MCH1 ON AUSP~OBJEK = MCH1~CUOBJ_BM
*    WHERE MCH1~MATNR = MAT AND MCH1~CHARG = BATCH AND AUSP~ATINN = VX_ATNUOM.

  CLEAR TBATCH.
  REFRESH TBATCH.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = MAT
      CHARG              = BATCH
      WERKS              = PLANT
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = TBATCH
    EXCEPTIONS
      NO_MATERIAL        = 1
      NO_BATCH           = 2
      NO_PLANT           = 3
      MATERIAL_NOT_FOUND = 4
      PLANT_NOT_FOUND    = 5
      NO_AUTHORITY       = 6
      BATCH_NOT_EXIST    = 7
      LOCK_ON_BATCH      = 8
      OTHERS             = 9.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZEXLENGTH'.
  IF SY-SUBRC EQ 0.
    EXLENG_LAMA = TBATCH-ATWTB.
  ENDIF.

ENDFORM.                    "GET_EXLENGHT_LAMA

*&---------------------------------------------------------------------*
*&      Form  GET_SLOC
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->ZVAL       text
*----------------------------------------------------------------------*
FORM GET_SLOC CHANGING ZVAL.
  CLEAR : ITHELP.
  REFRESH: ITHELP.
*  CALL FUNCTION 'DYNP_GET_STEPL'
*    IMPORTING
*      POVSTEPL = V_DYNINDEX.
*  READ TABLE IT_CHANGE INDEX V_DYNINDEX.
*  IF IT_CHANGE-WERKS IS INITIAL.
*    MESSAGE 'Plant Kosong!' TYPE 'I'.
*  ELSE.
*    CASE IT_CHANGE-WERKS.
*      WHEN '1000'.
  SELECT DISTINCT WERKS ZRRLGORT AS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
    FROM ZTMAP_SLOCRR
    WHERE ZTMAP_SLOCRR~WERKS IN ('1000','2000','TTA2')
    AND ZTMAP_SLOCRR~ZDESC NE ''.


*      WHEN '2000'.
*        SELECT DISTINCT WERKS ZRRLGORT AS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
*          FROM ZTMAP_SLOCRR
*          WHERE ZTMAP_SLOCRR~WERKS = '2000'.
*        CLEAR : ITHELP.
*        ITHELP-WERKS = '2000'.
*        ITHELP-LGORT = '2815'.
*        APPEND ITHELP.
*    ENDCASE.

  CLEAR : ITHELP.
  ITHELP-WERKS = '1000'.
  ITHELP-LGORT = '1815'.
  APPEND ITHELP.

  CLEAR : ITHELP.
  ITHELP-WERKS = '2000'.
  ITHELP-LGORT = '2815'.
  APPEND ITHELP.

  CLEAR : ITHELP.
  ITHELP-WERKS = 'TTA2'.
  ITHELP-LGORT = '2815'.
  APPEND ITHELP.

  LOOP AT ITHELP.
    SELECT SINGLE LGOBE INTO ITHELP-LGOBE
      FROM T001L
      WHERE WERKS = ITHELP-WERKS
      AND LGORT = ITHELP-LGORT.
    MODIFY ITHELP.
  ENDLOOP.

  DELETE ITHELP WHERE LGOBE IS INITIAL.
  SORT ITHELP BY WERKS LGORT ASCENDING.
  CALL FUNCTION 'F4IF_INT_TABLE_VALUE_REQUEST'
    EXPORTING
      RETFIELD        = 'LGORT'
      DYNPPROG        = SY-CPROG
      DYNPNR          = SY-DYNNR
      DYNPROFIELD     = 'IT_CHANGE-RSLOC'
      STEPL           = V_DYNINDEX
      VALUE_ORG       = 'S'
    TABLES
      VALUE_TAB       = ITHELP
    EXCEPTIONS
      PARAMETER_ERROR = 1
      NO_VALUES_FOUND = 2
      OTHERS          = 3.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
*  ENDIF.

ENDFORM.                    "GET_SLOC

*&---------------------------------------------------------------------*
*&      Form  CEKBASEFILM
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->DATA       text
*      -->FLAG       text
*----------------------------------------------------------------------*
FORM CEKBASEFILM USING DATA CHANGING FLAG.
  DATA: P_AUART LIKE AUFK-AUART,
        P_CHARG LIKE MSEG-CHARG,
        P_MATNR LIKE MSEG-MATNR,
        P_WERKS LIKE MSEG-WERKS,
        BATCHEXLENGASAL LIKE MSEG-CHARG,
        BATCHEXLEN LIKE MSEG-CHARG.

  SELECT AUFK~AUART FROM MSEG JOIN AUFK ON MSEG~AUFNR EQ AUFK~AUFNR
    INTO P_AUART WHERE MSEG~CHARG EQ DATA AND BWART EQ '101'.
  ENDSELECT.

  SELECT SINGLE CHARG WERKS MATNR FROM MSEG INTO (P_CHARG,P_WERKS,P_MATNR)
    WHERE CHARG EQ DATA AND BWART EQ '101'.

  IF P_AUART EQ 'ZBS1' OR P_AUART EQ 'ZBS2'.
    PERFORM CHANGEEXLENGTH USING DATA.
  ELSE.
    FLAG = '1'.

    CLEAR TBATCH.
    REFRESH TBATCH.
    CALL FUNCTION 'VB_INIT'
      EXPORTING
        INIT_RESET = 'X'.
    CALL FUNCTION 'VB_BATCH_GET_DETAIL'
      EXPORTING
        MATNR              = P_MATNR
        CHARG              = P_CHARG
        WERKS              = P_WERKS
        GET_CLASSIFICATION = 'X'
      TABLES
        CHAR_OF_BATCH      = TBATCH
      EXCEPTIONS
        NO_MATERIAL        = 1
        NO_BATCH           = 2
        NO_PLANT           = 3
        MATERIAL_NOT_FOUND = 4
        PLANT_NOT_FOUND    = 5
        NO_AUTHORITY       = 6
        BATCH_NOT_EXIST    = 7
        LOCK_ON_BATCH      = 8
        OTHERS             = 9.
    IF SY-SUBRC <> 0.
* Implement suitable error handling here
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZEXLENGTH'.
    IF SY-SUBRC EQ 0.
      REPLACE ALL OCCURRENCES OF ',' IN TBATCH-ATWTB WITH SPACE.
      CONDENSE TBATCH-ATWTB NO-GAPS.
      BATCHEXLEN = TBATCH-ATWTB.
    ENDIF.
    READ TABLE TBATCH WITH KEY ATNAM = 'ZZEXTRALENGTHASAL'.
    IF SY-SUBRC EQ 0.
      REPLACE ALL OCCURRENCES OF ',' IN TBATCH-ATWTB WITH SPACE.
      CONDENSE TBATCH-ATWTB NO-GAPS.
      BATCHEXLENGASAL = TBATCH-ATWTB.
    ENDIF.

    IF BATCHEXLEN EQ '0' .
      IT_CHANGE-EXLENG = BATCHEXLENGASAL.
    ENDIF.

    MODIFY IT_CHANGE TRANSPORTING EXLENG WHERE BATCHA EQ DATA.

  ENDIF.

ENDFORM.                    "CEKBASEFILM

*&---------------------------------------------------------------------*
*&      Form  CHANGEEXLENGTH
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->DATA       text
*----------------------------------------------------------------------*
FORM CHANGEEXLENGTH USING DATA.
  DATA:P_AUFNR LIKE MSEG-AUFNR,
       P_CHARG LIKE MSEG-CHARG,
       P_MATNR LIKE MSEG-MATNR,
       P_WERKS LIKE MSEG-WERKS.



  SELECT SINGLE AUFNR FROM MSEG INTO P_AUFNR
    WHERE CHARG EQ DATA AND BWART EQ '101'.

  SELECT SINGLE CHARG WERKS MATNR FROM MSEG INTO (P_CHARG,P_WERKS,P_MATNR)
    WHERE AUFNR EQ P_AUFNR AND BWART EQ '261'.



  CLEAR TBATCH.
  REFRESH TBATCH.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = P_MATNR
      CHARG              = P_CHARG
      WERKS              = P_WERKS
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = TBATCH
    EXCEPTIONS
      NO_MATERIAL        = 1
      NO_BATCH           = 2
      NO_PLANT           = 3
      MATERIAL_NOT_FOUND = 4
      PLANT_NOT_FOUND    = 5
      NO_AUTHORITY       = 6
      BATCH_NOT_EXIST    = 7
      LOCK_ON_BATCH      = 8
      OTHERS             = 9.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZEXLENGTH'.
  IF SY-SUBRC EQ 0.
    REPLACE ALL OCCURRENCES OF ',' IN TBATCH-ATWTB WITH SPACE.
    CONDENSE TBATCH-ATWTB NO-GAPS.
    IT_CHANGE-EXLENG = TBATCH-ATWTB.
  ENDIF.

  MODIFY IT_CHANGE TRANSPORTING EXLENG WHERE BATCHA EQ DATA.
ENDFORM.                    "CHANGEEXLENGTH

*&---------------------------------------------------------------------*
*&      Form  FILLDATA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM FILLDATA.
  DATA: EXLENG_LAMA LIKE AUSP-ATWRT,
        MSG TYPE STRING.
  CLEAR: EXLENG_LAMA.

  LOOP AT IT_CHANGE.
    IF IT_CHANGE-GRADEB NE ''.
      READ TABLE IT_GRADE WITH KEY VTVALUE = IT_CHANGE-GRADEB.
      IF SY-SUBRC EQ 0.
        CLEAR ATINN.
        PERFORM ATNAM USING 'ZZGRADE' CHANGING ATINN.
        SELECT SINGLE ATWTB INTO IT_CHANGE-DGRADE2
          FROM CAWNT
          JOIN CAWN ON CAWN~ATINN = CAWNT~ATINN AND CAWN~ATZHL = CAWNT~ATZHL
          WHERE CAWN~ATWRT = IT_CHANGE-GRADEB
          AND CAWN~ATINN = ATINN
          AND CAWNT~SPRAS EQ 'EN'.
        READ TABLE IT_CRITERIA WITH KEY VTLINENO = IT_GRADE-VTLINENO.
        IF SY-SUBRC EQ 0.
          CLEAR ATINN.
          PERFORM ATNAM USING 'ZZCRITERIA' CHANGING ATINN.
          IT_CHANGE-CRITB = IT_CRITERIA-VTVALUE.

          SELECT SINGLE ATWTB INTO IT_CHANGE-DCRITB
          FROM CAWNT
          JOIN CAWN ON CAWN~ATINN = CAWNT~ATINN AND CAWN~ATZHL = CAWNT~ATZHL
          WHERE CAWN~ATWRT = IT_CHANGE-CRITB
          AND CAWN~ATINN = ATINN
          AND CAWNT~SPRAS EQ 'EN'.
        ENDIF.
        IF IT_CHANGE-EXIDV IS NOT INITIAL.
          IF IT_CHANGE-CRITB EQ 'S'.
            CLEAR: IT_CHANGE-CRITB,IT_CHANGE-DGRADE2,IT_CHANGE-GRADEB,IT_CHANGE-DCRITB.
            MESSAGE  'Batch yang terikat HU tidak boleh memiliki criteria grade Scrap' TYPE 'I'.
*            REFRESH CONTROL 'TCHANGE' FROM SCREEN 0200.
            STOP.
          ENDIF.
        ENDIF.
      ELSE.
        CLEAR: IT_CHANGE-GRADEB,IT_CHANGE-CRITB.
        MESSAGE 'Grade tidak ditemukan!' TYPE 'I'.
        STOP.
      ENDIF.
    ENDIF.

    IF P_AUTH2 IS NOT INITIAL.
      SELECT SINGLE HROID ARBPL
      INTO (HROID, ARBPL)
      FROM CRHD
      WHERE ARBPL = 'QA-CRD' AND
            OBJTY = 'A'.

      SELECT OBJID
        INTO CORRESPONDING FIELDS OF TABLE IT_NIK
        FROM HRP1001
        WHERE SOBID = HROID AND
              OTYPE = 'P'.
      CLEAR MESG.
      READ TABLE IT_NIK WITH KEY OBJID = P_AUTH2.
      IF SY-SUBRC NE 0.
        JLH = 2.
        CONCATENATE U_CHANGE-AUTHOR 'NIK tidak ditemukan pada W.cntr' ARBPL '!' INTO MESG SEPARATED BY SPACE.
        MESSAGE  MESG TYPE 'I'.
        CLEAR: U_CHANGE-AUTHOR,U_CHANGE-WC.
        STOP.
      ENDIF.

      CLEAR:HROID,ARBPL,IT_NIK.
      REFRESH: IT_NIK.

    ENDIF.



    PERFORM GET_EXLENGHT_LAMA USING IT_CHANGE-MATNR IT_CHANGE-BATCHA IT_CHANGE-WERKS CHANGING EXLENG_LAMA.

    REPLACE ALL OCCURRENCES OF ',' IN EXLENG_LAMA WITH SPACE.
    CONDENSE EXLENG_LAMA NO-GAPS.
    IT_CHANGE-EXLENG = EXLENG_LAMA.

    PERFORM VALID_BERATCHAR USING IT_CHANGE-MATNR IT_CHANGE-BATCHA IT_CHANGE-WERKS.
*    PERFORM CEKPLANT_NEWCOMP USING IT_CHANGE-WERKS IT_CHANGE-BATCHA.



    MODIFY IT_CHANGE.

    IF P_LGORT2 IS INITIAL AND IT_CHANGE-CRITB EQ 'S'.
      MESSAGE 'Sloc Harus Di Isi Untuk Criteria Grade Scrap' TYPE 'I'.
      STOP.
    ENDIF.

    IF IT_CHANGE-EXIDV NE ''.
      CONCATENATE 'Batch' IT_CHANGE-BATCHA 'masih terikat dengan HU.' INTO MSG SEPARATED BY SPACE.
      CALL FUNCTION 'POPUP_TO_DISPLAY_TEXT_LO'
        EXPORTING
          TITEL        = 'Information'
          TEXTLINE1    = 'Informasi Batch HU!'
          TEXTLINE2    = ' '
          TEXTLINE3    = MSG
          START_COLUMN = 15
          START_ROW    = 6.

      STOP.
    ENDIF.

    "1st/2sd
    IF IT_CHANGE-CRITA EQ '1' OR IT_CHANGE-CRITA EQ '2'.
      IF IT_CHANGE-EXLENG IS INITIAL OR IT_CHANGE-EXLENG EQ '0'.
        CONCATENATE 'Batch' IT_CHANGE-BATCHA 'Tidak Memiliki Extra Length' INTO MSGEXLENG SEPARATED BY SPACE.
        MESSAGE MSGEXLENG TYPE 'I'.
        STOP.
      ENDIF.
    ENDIF.

    "1st/2sd -> rw/rs/bf
    IF IT_CHANGE-CRITA EQ '1' OR IT_CHANGE-CRITA EQ '2'.
      IF IT_CHANGE-CRITB EQ 'R' OR IT_CHANGE-CRITB EQ 'B'.
        IF IT_CHANGE-EXLENG IS INITIAL OR IT_CHANGE-EXLENG EQ '0'.
          CONCATENATE 'Batch' IT_CHANGE-BATCHA 'Tidak Memiliki Extra Length' INTO MSGEXLENG SEPARATED BY SPACE.
          MESSAGE MSGEXLENG TYPE 'I'.
          STOP.
        ENDIF.
      ENDIF.
    ENDIF.

    "rw/rs/bf -> scrap
    IF IT_CHANGE-CRITA EQ 'R' OR IT_CHANGE-CRITA EQ 'B'.
      IF IT_CHANGE-CRITB EQ 'S'.
        IT_CHANGE-EXLENG = ''.
      ENDIF.
    ENDIF.

*    CEK SLOC JR NA
    IF IT_CHANGE-CRITB EQ 'S'.
      DATA: FLAG_SLOC TYPE STRING,
            MSGSLOC TYPE STRING.

      PERFORM CHECK_SLOCJRNA USING IT_CHANGE-LGORT IT_CHANGE-WERKS CHANGING FLAG_SLOC.

      IF FLAG_SLOC EQ 'X'.
        CLEAR: IT_CHANGE-GRADEB,IT_CHANGE-CRITB.
        CONCATENATE 'Sloc Batch' IT_CHANGE-BATCHA 'Salah, Tidak Bisa Untuk di Kupas' INTO MSGSLOC SEPARATED BY SPACE.
        MESSAGE MSGSLOC TYPE 'I'.
        STOP.
      ENDIF.
    ENDIF.



    CLEAR: EXLENG_LAMA.
  ENDLOOP.


ENDFORM.                    "FILLDATA

*&---------------------------------------------------------------------*
*&      Form  CEK_OBLI
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM CEK_OBLI.
  CLEAR ITHELP.
  REFRESH ITHELP.

  RANGES: SLOCSCRAP FOR ZTMAP_SLOCRR-ZRRLGORT.

  IF P_CHARG2 IS INITIAL.
    MESSAGE 'Batch Harus Di Isi' TYPE 'I'.
    STOP.
  ENDIF.

  SELECT DISTINCT WERKS ZRRLGORT AS LGORT INTO CORRESPONDING FIELDS OF TABLE ITHELP
    FROM ZTMAP_SLOCRR
    WHERE ZTMAP_SLOCRR~WERKS IN ('1000','2000','TTA2').

  CLEAR : ITHELP.
  ITHELP-WERKS = '1000'.
  ITHELP-LGORT = '1815'.
  APPEND ITHELP.

  CLEAR : ITHELP.
  ITHELP-WERKS = '2000'.
  ITHELP-LGORT = '2815'.
  APPEND ITHELP.

  CLEAR : ITHELP.
  ITHELP-WERKS = 'TTA2'.
  ITHELP-LGORT = '2815'.
  APPEND ITHELP.


  LOOP AT ITHELP.
    SLOCSCRAP-SIGN   = 'I'.
    SLOCSCRAP-OPTION = 'EQ'.
    SLOCSCRAP-LOW = ITHELP-LGORT.
    APPEND SLOCSCRAP.
  ENDLOOP.

  IF P_LGORT2 IS NOT INITIAL.
    IF P_LGORT2 NOT IN SLOCSCRAP.
      MESSAGE 'Sloc Tidak Terdaftar' TYPE 'I'.
      STOP.
    ENDIF.
  ENDIF.


  IF P_AUTH2 IS INITIAL.
    MESSAGE 'Authorize Personal Harus Di Isi' TYPE 'I'.
    STOP.
  ENDIF.

  IF P_NMEMO2 IS INITIAL.
    MESSAGE 'Nomor Memo Harus Di Isi' TYPE 'I'.
    STOP.
  ENDIF.

ENDFORM.                    "CEK_OBLI

*&---------------------------------------------------------------------*
*&      Form  DISPLAY_FINAL
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
FORM DISPLAY_FINAL.
*  DATA: X_FCODE TYPE TABLE OF SY-UCOMM.
*  APPEND 'EXCEL' TO X_FCODE.
*  APPEND 'LAYOUT' TO X_FCODE.
*  SET PF-STATUS 'MAIN200' EXCLUDING X_FCODE.

  LOOP AT U_CHANGE.

    "1st/2sd
    IF U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2'.
      IF U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2'.

        IF U_CHANGE-NOROLB IS NOT INITIAL.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-NOROLB IS INITIAL.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_E1.
          U_CHANGE-LINE_COLOR = 'C610'.
        ENDIF.

        MODIFY U_CHANGE.
      ENDIF.
    ENDIF.

    "1st/2sd -> rw/rs/bf
    IF U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2'.
      IF U_CHANGE-CRITB EQ 'R' OR U_CHANGE-CRITB EQ 'B'.

        IF U_CHANGE-STATUSEXLENG EQ 'Sukses'.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ 'Error'.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_E1.
          U_CHANGE-LINE_COLOR = 'C610'.
        ENDIF.

        MODIFY U_CHANGE.
      ENDIF.
    ENDIF.
    "rw/rs/bf -> 1st/2sd
    IF U_CHANGE-CRITA EQ 'R' OR U_CHANGE-CRITA EQ 'B'.
      IF U_CHANGE-CRITB EQ '1' OR U_CHANGE-CRITB EQ '2'.

        IF U_CHANGE-STATUSEXLENG EQ 'Sukses'.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ 'Error'.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_E1.
          U_CHANGE-LINE_COLOR = 'C610'.
        ENDIF.

        MODIFY U_CHANGE.

      ENDIF.
    ENDIF.
    "rw/rs/bf -> rw/rs/bf
    IF U_CHANGE-CRITA EQ 'R' OR U_CHANGE-CRITA EQ 'B'.
      IF U_CHANGE-CRITB EQ 'B' OR U_CHANGE-CRITB EQ 'R'.

        IF U_CHANGE-NOROLB IS NOT INITIAL.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-NOROLB IS INITIAL.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_E1.
          U_CHANGE-LINE_COLOR = 'C610'.
        ENDIF.

        MODIFY U_CHANGE.

      ENDIF.
    ENDIF.
    "1st/2sd -> scrap
    IF U_CHANGE-CRITA EQ '1' OR U_CHANGE-CRITA EQ '2'.
      IF U_CHANGE-CRITB EQ 'S'.

        IF U_CHANGE-STATUSEXLENG EQ 'Sukses' AND U_CHANGE-STATUSKUPAS EQ 'Sukses'.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ 'Sukses' AND U_CHANGE-STATUSKUPAS EQ 'Error'.
          U_CHANGE-STATUS = 'Warning'.
          U_CHANGE-INDC = GCF_W1.
          U_CHANGE-LINE_COLOR = 'C311'.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ 'Error' AND U_CHANGE-STATUSKUPAS EQ 'Sukses'.
          U_CHANGE-STATUS = 'Warning'.
          U_CHANGE-INDC = GCF_W1.
          U_CHANGE-LINE_COLOR = 'C311'.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ 'Error' AND U_CHANGE-STATUSKUPAS EQ 'Error'.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_E1.
          U_CHANGE-LINE_COLOR = 'C610'.
        ENDIF.

        MODIFY U_CHANGE.

      ENDIF.
    ENDIF.
    "rw/rs/bf -> scrap
    IF U_CHANGE-CRITA EQ 'R' OR U_CHANGE-CRITA EQ 'B'.
      IF U_CHANGE-CRITB EQ 'S'.

        IF U_CHANGE-STATUSEXLENG EQ '' AND U_CHANGE-STATUSKUPAS EQ 'Sukses'.
          U_CHANGE-STATUS = 'Sukses'.
          U_CHANGE-INDC = GCF_S1.
        ENDIF.

        IF U_CHANGE-STATUSEXLENG EQ '' AND U_CHANGE-STATUSKUPAS EQ 'Error'.
          U_CHANGE-STATUS = 'Error'.
          U_CHANGE-INDC = GCF_W1.
          U_CHANGE-LINE_COLOR = 'C410'.
        ENDIF.

*        IF U_CHANGE-STATUSEXLENG EQ '' AND U_CHANGE-STATUSKUPAS EQ 'Sukses'.
*          U_CHANGE-STATUS = 'Error'.
*          U_CHANGE-INDC = GCF_W1.
*          U_CHANGE-LINE_COLOR = 'C410'.
*        ENDIF.
*
*        IF U_CHANGE-STATUSEXLENG EQ '' AND U_CHANGE-STATUSKUPAS EQ 'Error'.
*          U_CHANGE-STATUS = 'Error'.
*          U_CHANGE-INDC = GCF_E1.
*          U_CHANGE-LINE_COLOR = 'C610'.

*        ENDIF.

        MODIFY U_CHANGE.

      ENDIF.
    ENDIF.
  ENDLOOP.


  "TO ALV
  CLEAR: IT_FIELDCAT, WA_FIELDCAT.
  REFRESH IT_FIELDCAT.

  DATA : NO TYPE N LENGTH 3 VALUE 1.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '9'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='INDC'.
  WA_FIELDCAT-SELTEXT_M = 'Indikator'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '8'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='STATUS'.
  WA_FIELDCAT-SELTEXT_M = 'Status'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '20'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='POAJDS'.
  WA_FIELDCAT-SELTEXT_M = 'PO Adjustment'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '20'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='POKUPAS'.
  WA_FIELDCAT-SELTEXT_M = 'PO Kupas'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'MATNR'.
  WA_FIELDCAT-SELTEXT_M = 'Material'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '25'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'TYPE'.
  WA_FIELDCAT-SELTEXT_M = 'Type/Thickness Film'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '10'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'LENGHT'.
  WA_FIELDCAT-SELTEXT_M = 'Lenght'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '10'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='WEIGHT'.
  WA_FIELDCAT-SELTEXT_M = 'Weight'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '10'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'WIDTH'.
  WA_FIELDCAT-SELTEXT_M = 'Width'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

*
*
*  CLEAR WA_FIELDCAT.
*  NO = NO + 1.
*
*  WA_FIELDCAT-COL_POS = NO.
*  WA_FIELDCAT-INTLEN = '10'.
*  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
*  WA_FIELDCAT-FIELDNAME = 'CHARG'.
*  WA_FIELDCAT-SELTEXT_M = 'BATCH'.
*  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '10'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'WERKS'.
  WA_FIELDCAT-SELTEXT_M = 'Plant'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '4'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='LGORT'.
  WA_FIELDCAT-SELTEXT_M = 'Sloc'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '25'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'NOROLA'.
  WA_FIELDCAT-SELTEXT_M = 'Nomor Roll Asal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.



  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '25'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME = 'NOROLB'.
  WA_FIELDCAT-SELTEXT_M = 'Nomor Roll Baru'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='BATCHA'.
  WA_FIELDCAT-SELTEXT_M = 'Nomor Batch Asal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='NCHARG'.
  WA_FIELDCAT-SELTEXT_M = 'Nomor Batch Baru'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='GRADEA'.
  WA_FIELDCAT-SELTEXT_M = 'Grade Asal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='GRADEB'.
  WA_FIELDCAT-SELTEXT_M = 'Grade Baru'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '25'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='DGRADE'.
  WA_FIELDCAT-SELTEXT_M = 'Desc. Grade Asal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '25'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='DGRADE2'.
  WA_FIELDCAT-SELTEXT_M = 'Desc. Grade Baru'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='DCRITA'.
  WA_FIELDCAT-SELTEXT_M = 'Criteria Grade Asal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

*   CLEAR WA_FIELDCAT.
*  NO = NO + 1.
*
*  WA_FIELDCAT-COL_POS = NO.
*  WA_FIELDCAT-INTLEN = '15'.
*  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
*  WA_FIELDCAT-FIELDNAME ='NCHARG'.
*  WA_FIELDCAT-SELTEXT_M = 'Nomor Batch Baru'.
*  APPEND WA_FIELDCAT TO IT_FIELDCAT.

*   CLEAR WA_FIELDCAT.
*  NO = NO + 1.
*
*  WA_FIELDCAT-COL_POS = NO.
*  WA_FIELDCAT-INTLEN = '15'.
*  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
*  WA_FIELDCAT-FIELDNAME ='NOROLL2'.
*  WA_FIELDCAT-SELTEXT_M = 'Nomor Roll Baru'.
*  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='NMEMO'.
  WA_FIELDCAT-SELTEXT_M = 'Nomor Memo'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='AUTHOR'.
  WA_FIELDCAT-SELTEXT_M = 'Authorized Personal'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='RSLOC'.
  WA_FIELDCAT-SELTEXT_M = 'Sloc Raw Recycle'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='EXLENG'.
  WA_FIELDCAT-SELTEXT_M = 'Extra Length'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='STATUSEXLENG'.
  WA_FIELDCAT-SELTEXT_M = 'Status Adjs Exlength'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='STATUSKUPAS'.
  WA_FIELDCAT-SELTEXT_M = 'Status Kupas'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-NO_OUT = 'X'.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='LOGEXLENG'.
  WA_FIELDCAT-SELTEXT_M = 'Log Adjs Exlength'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-NO_OUT = 'X'.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='LOGKUPAS'.
  WA_FIELDCAT-SELTEXT_M = 'Log Kupas'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-NO_OUT = 'X'.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='LOGEXLENGCANCEL'.
  WA_FIELDCAT-SELTEXT_M = 'Log Cancel Adjs Exlength'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.

  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.
  WA_FIELDCAT-NO_OUT = 'X'.
  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='LOGKUPASCANCEL'.
  WA_FIELDCAT-SELTEXT_M = 'Log Cancel Kupas'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.



  CLEAR WA_FIELDCAT.
  NO = NO + 1.

  WA_FIELDCAT-COL_POS = NO.

  WA_FIELDCAT-INTLEN = '15'.
  WA_FIELDCAT-TABNAME = 'U_CHANGE'.
  WA_FIELDCAT-FIELDNAME ='SPRNT'.
  WA_FIELDCAT-SELTEXT_M = 'Print Status'.
  APPEND WA_FIELDCAT TO IT_FIELDCAT.



  IT_LAYOUT-INFO_FIELDNAME = 'LINE_COLOR'.

  CALL FUNCTION 'REUSE_ALV_GRID_DISPLAY'
    EXPORTING
      IS_LAYOUT                = IT_LAYOUT
      IT_FIELDCAT              = IT_FIELDCAT
*     I_CALLBACK_PF_STATUS_SET = 'MAIN200'
*     I_CALLBACK_USER_COMMAND  = ' '
*     I_SAVE                   = 'A'
    TABLES
      T_OUTTAB                 = U_CHANGE
    EXCEPTIONS
      PROGRAM_ERROR            = 1
      OTHERS                   = 2.
  .
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.


ENDFORM.                    "DISPLAY_FINAL

*&---------------------------------------------------------------------*
*&      Form  CHECK_SLOCJRNA
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->SLOC       text
*      -->FLAG       text
*----------------------------------------------------------------------*
FORM CHECK_SLOCJRNA USING SLOC PLANT CHANGING FLAG.
  DATA : BEGIN OF IT_SLOCNA OCCURS 0,
          WERKS LIKE T001L-WERKS,
          LGORT LIKE T001L-LGORT,
          LGOBE LIKE T001L-LGOBE.
  DATA : END OF IT_SLOCNA.

  RANGES: SLOCNA FOR T001L-LGORT.

  CLEAR:IT_SLOCNA,SLOCNA.
  REFRESH:IT_SLOCNA,SLOCNA.

  SELECT WERKS LGORT LGOBE FROM T001L INTO CORRESPONDING FIELDS OF TABLE IT_SLOCNA
    WHERE WERKS EQ PLANT
    AND LGOBE LIKE '%NA%'.

  LOOP AT IT_SLOCNA.
    SLOCNA-SIGN   = 'I'.
    SLOCNA-OPTION = 'EQ'.
    SLOCNA-LOW = IT_SLOCNA-LGORT.
    APPEND SLOCNA.
  ENDLOOP.

  SLOCNA-SIGN   = 'I'.
  SLOCNA-OPTION = 'EQ'.
  SLOCNA-LOW = '2802'.
  APPEND SLOCNA.

  SLOCNA-SIGN   = 'I'.
  SLOCNA-OPTION = 'EQ'.
  SLOCNA-LOW = '1802'.
  APPEND SLOCNA.

  SLOCNA-SIGN   = 'I'.
  SLOCNA-OPTION = 'EQ'.
  SLOCNA-LOW = '3802'.
  APPEND SLOCNA.

*  SLOCNA-SIGN   = 'I'.
*  SLOCNA-OPTION = 'EQ'.
*  SLOCNA-LOW = '2801'.
*  APPEND SLOCNA.

  IF SLOC NOT IN SLOCNA.
    FLAG = 'X'.
  ENDIF.


ENDFORM.                    "CHECK_SLOCJRNA

*&---------------------------------------------------------------------*
*&      Form  VALID_BERATCHAR
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->MAT        text
*      -->BATCH      text
*      -->PLANT      text
*----------------------------------------------------------------------*
FORM VALID_BERATCHAR USING MAT BATCH PLANT.

  DATA: BERATCONVERT TYPE STRING,
        BERATCONVERTTMP TYPE STRING,
        JMLROLL TYPE STRING,
        JMLROLLTMP TYPE STRING,
        MSG TYPE STRING,
        BERATROLL LIKE MCHB-CLABS,
        V_MCHB LIKE MCHB OCCURS 0 WITH HEADER LINE.

  CLEAR TBATCH.
  REFRESH TBATCH.
  CALL FUNCTION 'VB_INIT'
    EXPORTING
      INIT_RESET = 'X'.
  CALL FUNCTION 'VB_BATCH_GET_DETAIL'
    EXPORTING
      MATNR              = MAT
      CHARG              = BATCH
      WERKS              = PLANT
      GET_CLASSIFICATION = 'X'
    TABLES
      CHAR_OF_BATCH      = TBATCH
    EXCEPTIONS
      NO_MATERIAL        = 1
      NO_BATCH           = 2
      NO_PLANT           = 3
      MATERIAL_NOT_FOUND = 4
      PLANT_NOT_FOUND    = 5
      NO_AUTHORITY       = 6
      BATCH_NOT_EXIST    = 7
      LOCK_ON_BATCH      = 8
      OTHERS             = 9.
  IF SY-SUBRC <> 0.
* Implement suitable error handling here
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZCONVERSIONROLLKG'.
  IF SY-SUBRC EQ 0.
    BERATCONVERT = TBATCH-ATWTB.
  ENDIF.
  READ TABLE TBATCH WITH KEY ATNAM = 'ZZNUMBEROFROLL'.
  IF SY-SUBRC EQ 0.
    JMLROLLTMP = TBATCH-ATWTB.
  ENDIF.

  SELECT * FROM MCHB INTO CORRESPONDING FIELDS OF TABLE V_MCHB WHERE CHARG EQ BATCH.

  DELETE V_MCHB WHERE CLABS IS INITIAL.

  LOOP AT V_MCHB.
    BERATROLL = V_MCHB-CLABS.
  ENDLOOP.

  SPLIT BERATCONVERT AT SPACE INTO BERATCONVERT BERATCONVERTTMP.
  SPLIT JMLROLLTMP AT SPACE INTO JMLROLL JMLROLLTMP.

  REPLACE ALL OCCURRENCES OF ',' IN BERATCONVERT WITH SPACE.
  CONDENSE BERATCONVERT NO-GAPS.

  IF JMLROLL GT 1.
    CONCATENATE 'Batch' BATCH 'Memiliki Roll Characteristic Yang Lebih Dari 1' INTO MSG SEPARATED BY SPACE.
    MESSAGE MSG TYPE 'I'.
    STOP.

  ENDIF.

  IF BERATCONVERT NE BERATROLL.
    CONCATENATE 'Batch' BATCH 'Memiliki Berat Characteristic Yang Berbeda Dengan Berat Stok' INTO MSG SEPARATED BY SPACE.
    MESSAGE MSG TYPE 'I'.
    STOP.

  ENDIF.

ENDFORM.                    "VALID_BERATCHAR

*&---------------------------------------------------------------------*
*&      Form  CEKPLANT_NEWCOMP
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->PLANT      text
*      -->BATCH      text
*----------------------------------------------------------------------*
FORM CEKPLANT_NEWCOMP USING PLANT BATCH.
  DATA:ZWERKS LIKE MCHB-WERKS,
        MSG TYPE STRING.


  SELECT SINGLE WERKS FROM MCHB INTO ZWERKS
    WHERE CHARG EQ BATCH.

  IF ZWERKS EQ 'TTA2' OR ZWERKS EQ 'TTE2'.
    CONCATENATE 'Batch' BATCH 'Bukan Plant Trias' INTO MSG SEPARATED BY SPACE.
    MESSAGE MSG TYPE 'I'.
    STOP.

  ENDIF.

ENDFORM.                    "CEKPLANT_NEWCOMP

*&---------------------------------------------------------------------*
*&      Form  F_CALCULATE_LENGTH
*&---------------------------------------------------------------------*
*       text
*----------------------------------------------------------------------*
*      -->WEIGHT  text
*      -->WIDTH  text
*      -->GRAMMAGE   text
*      <--LENGTH  text
*----------------------------------------------------------------------*
FORM F_CALCULATE_LENGTH  USING    WEIGHT
                                  WIDTH
                                  GRAMMAGE
                         CHANGING LENGTH.

  DATA: V_WIDTHC LIKE AUSP-ATWRT .
  DATA: V_WEIGHTC LIKE AUSP-ATWRT .
  DATA: V_GRAMMAGEC LIKE AUSP-ATWRT .

  DATA: V_LENGTH TYPE MENGV .
  DATA: V_WIDTH TYPE MENGV .
  DATA: V_WEIGHT TYPE MENGV .
  DATA: V_GRAMMAGE TYPE MENGV .

  DATA: V_VAL TYPE STRING.
  DATA: V_DEC TYPE DECIMALS.

  V_WIDTHC     = WIDTH.
  V_WEIGHTC    = WEIGHT.
  V_GRAMMAGEC  = GRAMMAGE.

  REPLACE ALL OCCURRENCES OF ',' IN V_WIDTHC WITH ''.
  REPLACE ALL OCCURRENCES OF ',' IN V_WEIGHTC WITH ''.
  REPLACE ALL OCCURRENCES OF ',' IN V_GRAMMAGEC WITH ''.

  V_WIDTH     = V_WIDTHC.
  V_WEIGHT    = V_WEIGHTC.
  V_GRAMMAGE  = V_GRAMMAGEC.

  V_LENGTH = ( V_WEIGHT * 1000000 ) / ( V_WIDTH * V_GRAMMAGE ).

  WRITE V_LENGTH TO LENGTH.

  SPLIT LENGTH AT '.' INTO V_VAL V_DEC.

  IF V_DEC = 0.
    LENGTH = V_VAL.
  ENDIF.

ENDFORM.                    " F_CALCULATE_LENGTH