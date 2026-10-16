CLASS ltd_code_provider DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES if_ci_atc_source_code_provider.
    DATA mt_procedures TYPE if_ci_atc_source_code_provider=>ty_procedures.
    DATA mv_unbound TYPE abap_bool.
    DATA ms_unit TYPE if_ci_atc_source_code_provider=>ty_compilation_unit.
ENDCLASS.

CLASS ltd_code_provider IMPLEMENTATION.
  METHOD if_ci_atc_source_code_provider~get_procedures.
    ms_unit = compilation_unit.
    IF mv_unbound = abap_true.
      RETURN.
    ENDIF.
    CREATE DATA procedures.
    procedures->* = mt_procedures.
  ENDMETHOD.

  METHOD if_ci_atc_source_code_provider~get_called_procedure.
  ENDMETHOD.

  METHOD if_ci_atc_source_code_provider~object_to_comp_unit.
    compilation_unit-name = object-name.
  ENDMETHOD.

  METHOD if_ci_atc_source_code_provider~get_statement_location.
  ENDMETHOD.

  METHOD if_ci_atc_source_code_provider~get_statement_checksum.
  ENDMETHOD.
ENDCLASS.

* helpers to write statements as the code provider gives them: lexemes in upper case, columns from 0
CLASS ltcl_base DEFINITION ABSTRACT FOR TESTING.
  PROTECTED SECTION.
    CONSTANTS c_cu TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CU'.
    CONSTANTS c_co TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CO'.
    CONSTANTS c_ci TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CI'.
    CONSTANTS c_cm1 TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CM001'.
    CONSTANTS c_cm2 TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CM002'.
    CONSTANTS c_ccimp TYPE zif_lnt_source_reader=>ty_include VALUE 'ZCL_FOO=======================CCIMP'.

    "! Splits the code at spaces into tokens, starting at the given line and column
    METHODS statement
      IMPORTING
        iv_include          TYPE zif_lnt_source_reader=>ty_include DEFAULT 'ZTEST'
        iv_code             TYPE string
        iv_line             TYPE i DEFAULT 1
        iv_column           TYPE i DEFAULT 0
        it_pseudo_comments  TYPE if_ci_atc_source_code_provider=>ty_pseudo_comments OPTIONAL
      RETURNING
        VALUE(rs_statement) TYPE if_ci_atc_source_code_provider=>ty_statement.

    METHODS token
      IMPORTING
        iv_lexeme       TYPE string
        iv_line         TYPE i
        iv_column       TYPE i
      RETURNING
        VALUE(rs_token) TYPE if_ci_atc_source_code_provider=>ty_token.
ENDCLASS.

CLASS ltcl_base IMPLEMENTATION.
  METHOD statement.
    DATA lt_words TYPE string_table.

    rs_statement-include = iv_include.
    rs_statement-pseudo_comments = it_pseudo_comments.
    rs_statement-position-line = iv_line.
    rs_statement-position-column = iv_column.

    SPLIT iv_code AT ` ` INTO TABLE lt_words.
    DATA(lv_column) = iv_column.
    LOOP AT lt_words INTO DATA(lv_word).
      IF lv_word IS NOT INITIAL.
        INSERT token(
          iv_lexeme = lv_word
          iv_line   = iv_line
          iv_column = lv_column ) INTO TABLE rs_statement-tokens.
      ENDIF.
      lv_column = lv_column + strlen( lv_word ) + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD token.
    rs_token-lexeme = iv_lexeme.
    rs_token-position-line = iv_line.
    rs_token-position-column = iv_column.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_build_includes DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT INHERITING FROM ltcl_base.
  PRIVATE SECTION.
    METHODS positions FOR TESTING RAISING cx_static_check.
    METHODS multi_line FOR TESTING RAISING cx_static_check.
    METHODS chain FOR TESTING RAISING cx_static_check.
    METHODS chain_three_parts FOR TESTING RAISING cx_static_check.
    METHODS unsorted_and_duplicate FOR TESTING RAISING cx_static_check.
    METHODS pseudo_comment FOR TESTING RAISING cx_static_check.
    METHODS includes FOR TESTING RAISING cx_static_check.
    METHODS no_tokens FOR TESTING RAISING cx_static_check.

    METHODS source
      IMPORTING
        it_statements    TYPE if_ci_atc_source_code_provider=>ty_statements
        iv_include       TYPE zif_lnt_source_reader=>ty_include DEFAULT 'ZTEST'
      RETURNING
        VALUE(rt_source) TYPE string_table.
ENDCLASS.

CLASS ltcl_build_includes IMPLEMENTATION.
  METHOD source.
    DATA(lt_includes) = zcl_lnt_atc_source_reader=>build_includes( it_statements ).
    READ TABLE lt_includes WITH TABLE KEY include = iv_include INTO DATA(ls_include).
    cl_abap_unit_assert=>assert_subrc( ).
    rt_source = ls_include-source.
  ENDMETHOD.

  METHOD positions.
    DATA(lt_source) = source( VALUE #(
      ( statement( iv_code = `REPORT ZTEST` ) )
      ( statement( iv_code = `DATA  LV_FOO TYPE I` iv_line = 3 iv_column = 2 ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_source
      exp = VALUE string_table(
        ( `REPORT ZTEST.` )
        ( `` )
        ( `  DATA  LV_FOO TYPE I.` ) ) ).
  ENDMETHOD.

  METHOD multi_line.
    DATA(ls_statement) = statement( iv_code = `CALL METHOD FOO` iv_line = 1 iv_column = 0 ).
    INSERT token( iv_lexeme = `EXPORTING` iv_line = 2 iv_column = 2 ) INTO TABLE ls_statement-tokens.
    INSERT token( iv_lexeme = `BAR` iv_line = 3 iv_column = 4 ) INTO TABLE ls_statement-tokens.
    INSERT token( iv_lexeme = `=` iv_line = 3 iv_column = 8 ) INTO TABLE ls_statement-tokens.
    INSERT token( iv_lexeme = `1` iv_line = 3 iv_column = 10 ) INTO TABLE ls_statement-tokens.

    cl_abap_unit_assert=>assert_equals(
      act = source( VALUE #( ( ls_statement ) ) )
      exp = VALUE string_table(
        ( `CALL METHOD FOO` )
        ( `  EXPORTING` )
        ( `    BAR = 1.` ) ) ).
  ENDMETHOD.

  METHOD chain.
* a chained declaration of a and b on one line
    DATA(ls_second) = statement( iv_code = `DATA` ).
    INSERT token( iv_lexeme = `B` iv_line = 1 iv_column = 16 ) INTO TABLE ls_second-tokens.
    INSERT token( iv_lexeme = `TYPE` iv_line = 1 iv_column = 18 ) INTO TABLE ls_second-tokens.
    INSERT token( iv_lexeme = `I` iv_line = 1 iv_column = 23 ) INTO TABLE ls_second-tokens.

    cl_abap_unit_assert=>assert_equals(
      act = source( VALUE #(
        ( statement( iv_code = `DATA  A TYPE I` ) )
        ( ls_second ) ) )
      exp = VALUE string_table( ( `DATA: A TYPE I, B TYPE I.` ) ) ).
  ENDMETHOD.

  METHOD chain_three_parts.
* a chained WRITE of a, b and c, one part per line
    DATA(lt_statements) = VALUE if_ci_atc_source_code_provider=>ty_statements(
      ( statement( iv_code = `WRITE  / A` ) ) ).
    DATA(ls_statement) = statement( iv_code = `WRITE` ).
    INSERT token( iv_lexeme = `/` iv_line = 2 iv_column = 7 ) INTO TABLE ls_statement-tokens.
    INSERT token( iv_lexeme = `B` iv_line = 2 iv_column = 9 ) INTO TABLE ls_statement-tokens.
    INSERT ls_statement INTO TABLE lt_statements.
    ls_statement = statement( iv_code = `WRITE` ).
    INSERT token( iv_lexeme = `/` iv_line = 3 iv_column = 7 ) INTO TABLE ls_statement-tokens.
    INSERT token( iv_lexeme = `C` iv_line = 3 iv_column = 9 ) INTO TABLE ls_statement-tokens.
    INSERT ls_statement INTO TABLE lt_statements.

    cl_abap_unit_assert=>assert_equals(
      act = source( lt_statements )
      exp = VALUE string_table(
        ( `WRITE: / A,` )
        ( `       / B,` )
        ( `       / C.` ) ) ).
  ENDMETHOD.

  METHOD unsorted_and_duplicate.
    DATA(ls_first) = statement( iv_code = `REPORT ZTEST` ).
    DATA(ls_second) = statement( iv_code = `WRITE FOO` iv_line = 2 ).

    cl_abap_unit_assert=>assert_equals(
      act = source( VALUE #( ( ls_second ) ( ls_first ) ( ls_second ) ) )
      exp = VALUE string_table(
        ( `REPORT ZTEST.` )
        ( `WRITE FOO.` ) ) ).
  ENDMETHOD.

  METHOD pseudo_comment.
    cl_abap_unit_assert=>assert_equals(
      act = source( VALUE #(
        ( statement( iv_code = `CALL FUNCTION 'FOO'` it_pseudo_comments = VALUE #( ( `CI_SUBRC` ) ) ) )
        ( statement( iv_code = `SELECT * FROM T100 INTO TABLE LT_FOO` iv_line = 2 it_pseudo_comments = VALUE #( ( `"#EC CI_NOWHERE` ) ) ) ) ) )
      exp = VALUE string_table(
        ( `CALL FUNCTION 'FOO'. "#EC CI_SUBRC` )
        ( `SELECT * FROM T100 INTO TABLE LT_FOO. "#EC CI_NOWHERE` ) ) ).
  ENDMETHOD.

  METHOD includes.
    DATA(lt_includes) = zcl_lnt_atc_source_reader=>build_includes( VALUE #(
      ( statement( iv_include = c_cm1 iv_code = `METHOD BAR` ) )
      ( statement( iv_include = c_cu iv_code = `CLASS ZCL_FOO DEFINITION PUBLIC` ) )
      ( statement( iv_include = c_cm1 iv_code = `ENDMETHOD` iv_line = 2 ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_includes )
      exp = 2 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_includes[ include = c_cm1 ]-source
      exp = VALUE string_table(
        ( `METHOD BAR.` )
        ( `ENDMETHOD.` ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_includes[ include = c_cu ]-source
      exp = VALUE string_table( ( `CLASS ZCL_FOO DEFINITION PUBLIC.` ) ) ).
  ENDMETHOD.

  METHOD no_tokens.
    cl_abap_unit_assert=>assert_initial( zcl_lnt_atc_source_reader=>build_includes( VALUE #(
      ( include = 'ZTEST' ) ) ) ).
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_build_files DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT INHERITING FROM ltcl_base.
  PRIVATE SECTION.
    DATA mt_files TYPE zif_lnt_source_reader=>ty_files.
    DATA mt_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    METHODS clas FOR TESTING RAISING cx_static_check.
    METHODS clas_without_definition FOR TESTING RAISING cx_static_check.
    METHODS intf FOR TESTING RAISING cx_static_check.
    METHODS prog FOR TESTING RAISING cx_static_check.
    METHODS fugr FOR TESTING RAISING cx_static_check.
    METHODS unknown_type FOR TESTING RAISING cx_static_check.

    METHODS build
      IMPORTING
        iv_object_type TYPE csequence
        iv_object_name TYPE csequence
        it_includes    TYPE zcl_lnt_atc_source_reader=>ty_include_sources.
ENDCLASS.

CLASS ltcl_build_files IMPLEMENTATION.
  METHOD build.
    zcl_lnt_atc_source_reader=>build_files(
      EXPORTING
        iv_object_type = iv_object_type
        iv_object_name = iv_object_name
        it_includes    = it_includes
      IMPORTING
        et_files       = mt_files
        et_line_map    = mt_line_map ).
  ENDMETHOD.

  METHOD clas.
    build(
      iv_object_type = 'CLAS'
      iv_object_name = 'ZCL_FOO'
      it_includes    = VALUE #(
        ( include = c_cu source = VALUE #(
          ( `CLASS ZCL_FOO DEFINITION PUBLIC.` )
          ( `  PUBLIC SECTION.` )
          ( `    METHODS BAR.` ) ) )
        ( include = c_co source = VALUE #( ( `  PROTECTED SECTION.` ) ) )
        ( include = c_ci source = VALUE #( ( `  PRIVATE SECTION.` ) ) )
        ( include = c_cm1 source = VALUE #(
          ( `  METHOD BAR.` )
          ( `    X = 1.` )
          ( `  ENDMETHOD.` ) ) )
        ( include = c_cm2 source = VALUE #(
          ( `  METHOD MOO.` )
          ( `  ENDMETHOD.` ) ) )
        ( include = c_ccimp source = VALUE #( ( `CLASS LCL_BAR IMPLEMENTATION.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = mt_files
      exp = VALUE zif_lnt_source_reader=>ty_files(
        ( filename = `zcl_foo.clas.abap` source = VALUE #(
          ( `CLASS ZCL_FOO DEFINITION PUBLIC.` )
          ( `  PUBLIC SECTION.` )
          ( `    METHODS BAR.` )
          ( `  PROTECTED SECTION.` )
          ( `  PRIVATE SECTION.` )
          ( `ENDCLASS.` )
          ( `` )
          ( `CLASS zcl_foo IMPLEMENTATION.` )
          ( `  METHOD BAR.` )
          ( `    X = 1.` )
          ( `  ENDMETHOD.` )
          ( `` )
          ( `  METHOD MOO.` )
          ( `  ENDMETHOD.` )
          ( `` )
          ( `ENDCLASS.` ) ) )
        ( filename = `zcl_foo.clas.locals_imp.abap` source = VALUE #( ( `CLASS LCL_BAR IMPLEMENTATION.` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_line_map
      exp = VALUE zif_lnt_source_reader=>ty_line_maps(
        ( filename = `zcl_foo.clas.abap` from_row = 1 to_row = 3 include = c_cu first_row = 1 )
        ( filename = `zcl_foo.clas.abap` from_row = 4 to_row = 4 include = c_co first_row = 1 )
        ( filename = `zcl_foo.clas.abap` from_row = 5 to_row = 5 include = c_ci first_row = 1 )
        ( filename = `zcl_foo.clas.abap` from_row = 9 to_row = 11 include = c_cm1 first_row = 1 )
        ( filename = `zcl_foo.clas.abap` from_row = 13 to_row = 14 include = c_cm2 first_row = 1 )
        ( filename = `zcl_foo.clas.locals_imp.abap` from_row = 1 to_row = 1 include = c_ccimp first_row = 1 ) ) ).
  ENDMETHOD.

  METHOD clas_without_definition.
    build(
      iv_object_type = 'CLAS'
      iv_object_name = 'ZCL_FOO'
      it_includes    = VALUE #( ( include = c_ccimp source = VALUE #( ( `CLASS LCL_BAR IMPLEMENTATION.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_initial( mt_files ).
    cl_abap_unit_assert=>assert_initial( mt_line_map ).
  ENDMETHOD.

  METHOD intf.
    build(
      iv_object_type = 'INTF'
      iv_object_name = 'ZIF_FOO'
      it_includes    = VALUE #( ( include = 'ZIF_FOO=======================IU' source = VALUE #(
        ( `INTERFACE ZIF_FOO PUBLIC.` )
        ( `ENDINTERFACE.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = mt_files
      exp = VALUE zif_lnt_source_reader=>ty_files( ( filename = `zif_foo.intf.abap` source = VALUE #(
        ( `INTERFACE ZIF_FOO PUBLIC.` )
        ( `ENDINTERFACE.` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_line_map
      exp = VALUE zif_lnt_source_reader=>ty_line_maps(
        ( filename = `zif_foo.intf.abap` from_row = 1 to_row = 2 include = 'ZIF_FOO=======================IU' first_row = 1 ) ) ).
  ENDMETHOD.

  METHOD prog.
* other includes of the program are objects of their own
    build(
      iv_object_type = 'PROG'
      iv_object_name = 'ztest'
      it_includes    = VALUE #(
        ( include = 'ZTEST' source = VALUE #( ( `REPORT ZTEST.` ) ( `INCLUDE ZTEST_TOP.` ) ) )
        ( include = 'ZTEST_TOP' source = VALUE #( ( `DATA FOO TYPE I.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = mt_files
      exp = VALUE zif_lnt_source_reader=>ty_files( ( filename = `ztest.prog.abap` source = VALUE #(
        ( `REPORT ZTEST.` )
        ( `INCLUDE ZTEST_TOP.` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_line_map[ 1 ]-include
      exp = 'ZTEST' ).
  ENDMETHOD.

  METHOD fugr.
    build(
      iv_object_type = 'FUGR'
      iv_object_name = '/FOO/BAR'
      it_includes    = VALUE #(
        ( include = '/FOO/LBARTOP' source = VALUE #( ( `FUNCTION-POOL /FOO/BAR.` ) ) )
        ( include = '/FOO/LBARU01' source = VALUE #( ( `FUNCTION /FOO/MOO.` ) ( `ENDFUNCTION.` ) ) )
        ( include = '/FOO/SAPLBAR' source = VALUE #( ( `INCLUDE /FOO/LBARTOP.` ) ) )
        ( include = 'ZOTHER' source = VALUE #( ( `DATA FOO TYPE I.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( mt_files )
      exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_files[ 1 ]-filename
      exp = `#foo#bar.fugr.#foo#saplbar.abap` ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_files[ 2 ]-filename
      exp = `#foo#bar.fugr.#foo#lbartop.abap` ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_files[ 3 ]-filename
      exp = `#foo#bar.fugr.#foo#lbaru01.abap` ).
    cl_abap_unit_assert=>assert_equals(
      act = mt_line_map[ 3 ]
      exp = VALUE zif_lnt_source_reader=>ty_line_map(
        filename  = `#foo#bar.fugr.#foo#lbaru01.abap`
        from_row  = 1
        to_row    = 2
        include   = '/FOO/LBARU01'
        first_row = 1 ) ).
  ENDMETHOD.

  METHOD unknown_type.
    build(
      iv_object_type = 'TABL'
      iv_object_name = 'ZTEST'
      it_includes    = VALUE #( ( include = 'ZTEST' source = VALUE #( ( `REPORT ZTEST.` ) ) ) ) ).

    cl_abap_unit_assert=>assert_initial( mt_files ).
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_read DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT INHERITING FROM ltcl_base.
  PRIVATE SECTION.
    DATA mo_provider TYPE REF TO ltd_code_provider.
    DATA mi_reader TYPE REF TO zif_lnt_source_reader.

    METHODS setup.
    METHODS teardown.
    METHODS clas FOR TESTING RAISING cx_static_check.
    METHODS no_procedures FOR TESTING RAISING cx_static_check.
    METHODS no_code_provider FOR TESTING RAISING cx_static_check.
    METHODS run_rule FOR TESTING RAISING cx_static_check.

    METHODS set_class.
ENDCLASS.

CLASS ltcl_read IMPLEMENTATION.
  METHOD setup.
    mo_provider = NEW ltd_code_provider( ).
    mi_reader = NEW zcl_lnt_atc_source_reader( mo_provider ).
  ENDMETHOD.

  METHOD teardown.
    zcl_lnt_utils=>set_source_reader( VALUE #( ) ).
  ENDMETHOD.

  METHOD set_class.
* the statements come per procedure, the class definition in one, each method in another
    mo_provider->mt_procedures = VALUE #(
      ( id = VALUE #( name = `ZCL_FOO` ) statements = VALUE #(
        ( statement( iv_include = c_cu iv_code = `CLASS ZCL_FOO DEFINITION PUBLIC` ) )
        ( statement( iv_include = c_cu iv_code = `PUBLIC SECTION` iv_line = 2 iv_column = 2 ) )
        ( statement( iv_include = c_cu iv_code = `METHODS BAR` iv_line = 3 iv_column = 4 ) )
        ( statement( iv_include = c_co iv_code = `PROTECTED SECTION` iv_column = 2 ) )
        ( statement( iv_include = c_ci iv_code = `PRIVATE SECTION` iv_column = 2 ) ) ) )
      ( id = VALUE #( name = `BAR` ) statements = VALUE #(
        ( statement( iv_include = c_cm1 iv_code = `METHOD BAR` iv_column = 2 ) )
        ( statement( iv_include = c_cm1 iv_code = `FOO BAR MOO` iv_line = 2 iv_column = 4 ) )
        ( statement( iv_include = c_cm1 iv_code = `ENDMETHOD` iv_line = 3 iv_column = 2 ) ) ) ) ).
  ENDMETHOD.

  METHOD clas.
    DATA lt_files TYPE zif_lnt_source_reader=>ty_files.
    DATA lt_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    set_class( ).

    mi_reader->read(
      EXPORTING
        iv_object_type = 'CLAS'
        iv_object_name = 'ZCL_FOO'
      IMPORTING
        et_files       = lt_files
        et_line_map    = lt_line_map ).

    cl_abap_unit_assert=>assert_equals(
      act = mo_provider->ms_unit-name
      exp = 'ZCL_FOO' ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_files
      exp = VALUE zif_lnt_source_reader=>ty_files( ( filename = `zcl_foo.clas.abap` source = VALUE #(
        ( `CLASS ZCL_FOO DEFINITION PUBLIC.` )
        ( `  PUBLIC SECTION.` )
        ( `    METHODS BAR.` )
        ( `  PROTECTED SECTION.` )
        ( `  PRIVATE SECTION.` )
        ( `ENDCLASS.` )
        ( `` )
        ( `CLASS zcl_foo IMPLEMENTATION.` )
        ( `  METHOD BAR.` )
        ( `    FOO BAR MOO.` )
        ( `  ENDMETHOD.` )
        ( `` )
        ( `ENDCLASS.` ) ) ) ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_line_map )
      exp = 4 ).
  ENDMETHOD.

  METHOD no_procedures.
    DATA lt_files TYPE zif_lnt_source_reader=>ty_files.

    mo_provider->mv_unbound = abap_true.

    mi_reader->read(
      EXPORTING
        iv_object_type = 'CLAS'
        iv_object_name = 'ZCL_FOO'
      IMPORTING
        et_files       = lt_files ).

    cl_abap_unit_assert=>assert_initial( lt_files ).
  ENDMETHOD.

  METHOD no_code_provider.
    DATA lt_files TYPE zif_lnt_source_reader=>ty_files.

    NEW zcl_lnt_atc_source_reader( VALUE #( ) )->zif_lnt_source_reader~read(
      EXPORTING
        iv_object_type = 'CLAS'
        iv_object_name = 'ZCL_FOO'
      IMPORTING
        et_files       = lt_files ).

    cl_abap_unit_assert=>assert_initial( lt_files ).
  ENDMETHOD.

  METHOD run_rule.
* end to end, the parser error in the method is reported on the method include
    set_class( ).
    zcl_lnt_utils=>set_source_reader( VALUE #( ) ).

    DATA(lt_findings) = zcl_lnt_utils=>run_rule(
      io_rule        = NEW zcl_lnt_parser_error( )
      ii_reader      = mi_reader
      iv_object_type = 'CLAS'
      iv_object_name = 'ZCL_FOO' ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_findings )
      exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_findings[ 1 ]-include
      exp = c_cm1 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_findings[ 1 ]-line
      exp = 2 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_findings[ 1 ]-column
      exp = 5 ).
  ENDMETHOD.
ENDCLASS.
