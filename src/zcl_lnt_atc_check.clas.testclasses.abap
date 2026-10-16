CLASS ltd_reader DEFINITION FINAL FOR TESTING.
  PUBLIC SECTION.
    INTERFACES zif_lnt_source_reader.
    DATA mt_files TYPE zif_lnt_source_reader=>ty_files.
    DATA mt_line_map TYPE zif_lnt_source_reader=>ty_line_maps.
ENDCLASS.

CLASS ltd_reader IMPLEMENTATION.
  METHOD zif_lnt_source_reader~read.
    et_files = mt_files.
    et_line_map = mt_line_map.
  ENDMETHOD.
ENDCLASS.

CLASS ltcl_check DEFINITION FINAL FOR TESTING RISK LEVEL HARMLESS DURATION SHORT.
  PRIVATE SECTION.
    METHODS setup.
    METHODS teardown.
    METHODS run_parser_error FOR TESTING RAISING cx_static_check.
    METHODS run_double_space FOR TESTING RAISING cx_static_check.
    METHODS run_without_source FOR TESTING RAISING cx_static_check.
    METHODS run_unknown_type FOR TESTING RAISING cx_static_check.
    METHODS meta_data FOR TESTING RAISING cx_static_check.
    METHODS meta_data_pseudo_comment FOR TESTING RAISING cx_static_check.
    METHODS no_prerequisites FOR TESTING RAISING cx_static_check.
    METHODS to_atc_findings FOR TESTING RAISING cx_static_check.

    METHODS run
      IMPORTING
        ii_check           TYPE REF TO if_ci_atc_check
        iv_object_type     TYPE csequence DEFAULT 'PROG'
      RETURNING
        VALUE(rt_findings) TYPE if_ci_atc_check=>ty_findings.
ENDCLASS.

CLASS ltcl_check IMPLEMENTATION.
  METHOD setup.
    DATA(lo_reader) = NEW ltd_reader( ).
    lo_reader->mt_files = VALUE #( ( filename = `ztest.prog.abap` source = VALUE #(
      ( `REPORT ztest.` )
      ( `DATA lv_foo TYPE i.` )
      ( ` foo bar moo.` ) ) ) ).
    lo_reader->mt_line_map = VALUE #( (
      filename  = `ztest.prog.abap`
      from_row  = 1
      to_row    = 3
      include   = 'ZTEST'
      first_row = 1 ) ).
    zcl_lnt_utils=>set_source_reader( lo_reader ).
  ENDMETHOD.

  METHOD teardown.
    zcl_lnt_utils=>set_source_reader( VALUE #( ) ).
  ENDMETHOD.

  METHOD run.
    rt_findings = ii_check->run(
      object        = VALUE #( type = iv_object_type name = 'ZTEST' )
      data_provider = VALUE #( ) ).
  ENDMETHOD.

  METHOD run_parser_error.
    DATA(lt_findings) = run( NEW zcl_lnc_parser_error( ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_findings )
      exp = 1 ).
    DATA(ls_finding) = lt_findings[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-code
      exp = zcl_lnt_atc_meta_data=>c_code-error ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-location-object
      exp = VALUE if_ci_atc_check=>ty_object( type = 'PROG' name = 'ZTEST' ) ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-location-position-line
      exp = 3 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_finding-location-position-column
      exp = 1 ).
    cl_abap_unit_assert=>assert_char_cp(
      act = ls_finding-parameters-param_1
      exp = '*Statement does not exist*' ).
  ENDMETHOD.

  METHOD run_double_space.
* a second generated check on the same, cached, source
    run( NEW zcl_lnc_parser_error( ) ).
    DATA(lt_findings) = run( NEW zcl_lnc_double_space( ) ).

    cl_abap_unit_assert=>assert_initial( lt_findings ).
  ENDMETHOD.

  METHOD run_without_source.
* no injected reader and no data provider, as when the ATC gives no source
    zcl_lnt_utils=>set_source_reader( VALUE #( ) ).

    cl_abap_unit_assert=>assert_initial( run( NEW zcl_lnc_parser_error( ) ) ).
  ENDMETHOD.

  METHOD run_unknown_type.
    cl_abap_unit_assert=>assert_initial( run(
      ii_check       = NEW zcl_lnc_parser_error( )
      iv_object_type = 'TABL' ) ).
  ENDMETHOD.

  METHOD meta_data.
    DATA(li_meta) = CAST if_ci_atc_check( NEW zcl_lnc_parser_error( ) )->get_meta_data( ).

    cl_abap_unit_assert=>assert_equals(
      act = li_meta->get_description( )
      exp = `abaplint - Parser error` ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( li_meta->get_checked_object_types( ) )
      exp = 4 ).
    cl_abap_unit_assert=>assert_equals(
      act = li_meta->is_remote_enabled( )
      exp = abap_true ).
    cl_abap_unit_assert=>assert_initial( li_meta->get_attributes( ) ).
    cl_abap_unit_assert=>assert_initial( li_meta->get_quickfix_code_infos( ) ).

    DATA(lt_codes) = li_meta->get_finding_code_infos( ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_codes )
      exp = 4 ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-error ]-severity
      exp = if_ci_atc_check=>finding_severities-error ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-warning ]-severity
      exp = if_ci_atc_check=>finding_severities-warning ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-info ]-severity
      exp = if_ci_atc_check=>finding_severities-note ).
    cl_abap_unit_assert=>assert_equals(
      act = lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-dump ]-severity
      exp = if_ci_atc_check=>finding_severities-error ).
    cl_abap_unit_assert=>assert_initial( lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-error ]-pseudo_comment ).
  ENDMETHOD.

  METHOD meta_data_pseudo_comment.
    DATA(lt_codes) = CAST if_ci_atc_check( NEW zcl_lnc_check_subrc( ) )->get_meta_data( )->get_finding_code_infos( ).

    cl_abap_unit_assert=>assert_equals(
      act = lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-warning ]-pseudo_comment
      exp = `CI_SUBRC` ).
    cl_abap_unit_assert=>assert_initial( lt_codes[ code = zcl_lnt_atc_meta_data=>c_code-dump ]-pseudo_comment ).
  ENDMETHOD.

  METHOD no_prerequisites.
    DATA(li_check) = CAST if_ci_atc_check( NEW zcl_lnc_parser_error( ) ).

    li_check->set_attributes( VALUE #( ) ).
    li_check->set_assistant_factory( VALUE #( ) ).
    cl_abap_unit_assert=>assert_initial( li_check->verify_prerequisites( ) ).
  ENDMETHOD.

  METHOD to_atc_findings.
    DATA(lt_findings) = zcl_lnt_atc_check=>to_atc_findings( VALUE #(
      ( include = 'ZA' line = 1 column = 1 kind = zcl_lnt_utils=>c_kind-error code = zcl_lnt_utils=>c_code-issue text = `a` )
      ( include = 'ZB' line = 2 column = 0 kind = zcl_lnt_utils=>c_kind-warning code = zcl_lnt_utils=>c_code-issue text = `b` )
      ( include = 'ZC' line = 3 column = 300 kind = zcl_lnt_utils=>c_kind-note code = zcl_lnt_utils=>c_code-issue text = `c` )
      ( include = 'ZD' line = 4 column = 1 kind = zcl_lnt_utils=>c_kind-error code = zcl_lnt_utils=>c_code-dump text = `d` ) ) ).

    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_findings )
      exp = 4 ).
    LOOP AT lt_findings INTO DATA(ls_finding).
      CASE ls_finding-location-object-name.
        WHEN 'ZA'.
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-code
            exp = zcl_lnt_atc_meta_data=>c_code-error ).
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-location-position-column
            exp = 0 ).
        WHEN 'ZB'.
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-code
            exp = zcl_lnt_atc_meta_data=>c_code-warning ).
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-location-position-column
            exp = 0 ).
        WHEN 'ZC'.
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-code
            exp = zcl_lnt_atc_meta_data=>c_code-info ).
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-location-position-column
            exp = 255 ).
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-parameters-param_1
            exp = `c` ).
        WHEN 'ZD'.
          cl_abap_unit_assert=>assert_equals(
            act = ls_finding-code
            exp = zcl_lnt_atc_meta_data=>c_code-dump ).
        WHEN OTHERS.
          cl_abap_unit_assert=>fail( 'unexpected finding' ).
      ENDCASE.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
