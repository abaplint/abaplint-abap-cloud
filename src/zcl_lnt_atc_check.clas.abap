"! Runs one abaplint rule as an ATC check, the generated checks in src/checks inherit from this class
CLASS zcl_lnt_atc_check DEFINITION PUBLIC ABSTRACT CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_ci_atc_check.

    "! @parameter iv_pseudo_comment | Without the leading "#EC, like CI_SUBRC
    METHODS constructor
      IMPORTING
        iv_key            TYPE string
        iv_title          TYPE string
        iv_pseudo_comment TYPE string OPTIONAL.

    "! Maps findings from zcl_lnt_utils to ATC findings
    CLASS-METHODS to_atc_findings
      IMPORTING
        it_findings        TYPE zcl_lnt_utils=>ty_findings
      RETURNING
        VALUE(rt_findings) TYPE if_ci_atc_check=>ty_findings.

  PROTECTED SECTION.
    DATA mv_key TYPE string.
    DATA mv_title TYPE string.
    DATA mv_pseudo_comment TYPE string.
    DATA mo_assistant_factory TYPE REF TO cl_ci_atc_assistant_factory.

    METHODS create_rule ABSTRACT
      RETURNING
        VALUE(ri_rule) TYPE REF TO zif_lnt_rule.

  PRIVATE SECTION.
    CLASS-METHODS to_code
      IMPORTING
        is_finding     TYPE zcl_lnt_utils=>ty_finding
      RETURNING
        VALUE(rv_code) TYPE if_ci_atc_check=>ty_finding_code.
ENDCLASS.

CLASS zcl_lnt_atc_check IMPLEMENTATION.
  METHOD constructor.
    mv_key = iv_key.
    mv_title = iv_title.
    mv_pseudo_comment = iv_pseudo_comment.
  ENDMETHOD.

  METHOD if_ci_atc_check~get_meta_data.
    meta_data = NEW zcl_lnt_atc_meta_data(
      iv_title          = mv_title
      iv_pseudo_comment = mv_pseudo_comment ).
  ENDMETHOD.

  METHOD if_ci_atc_check~set_assistant_factory.
    mo_assistant_factory = factory.
  ENDMETHOD.

  METHOD if_ci_atc_check~verify_prerequisites.
    CLEAR verification_findings.
  ENDMETHOD.

  METHOD if_ci_atc_check~set_attributes.
* no attributes, the rules run with their default configuration
  ENDMETHOD.

  METHOD if_ci_atc_check~run.
    DATA(li_reader) = zcl_lnt_utils=>get_source_reader( ).
    IF li_reader IS NOT BOUND.
      IF data_provider IS NOT BOUND.
        RETURN.
      ENDIF.
      li_reader = NEW zcl_lnt_atc_source_reader( data_provider->get_code_provider( ) ).
    ENDIF.

    findings = to_atc_findings( zcl_lnt_utils=>run_rule(
      io_rule        = create_rule( )
      ii_reader      = li_reader
      iv_object_type = object-type
      iv_object_name = object-name ) ).
  ENDMETHOD.

  METHOD to_atc_findings.
    LOOP AT it_findings INTO DATA(ls_finding).
* abaplint columns start at 1, the token columns at zcl_lnt_atc_source_reader=>c_first_column
      DATA(lv_column) = ls_finding-column - 1 + zcl_lnt_atc_source_reader=>c_first_column.
      IF lv_column < 0.
        lv_column = 0.
      ELSEIF lv_column > 255.
        lv_column = 255.
      ENDIF.

      INSERT VALUE #(
        code       = to_code( ls_finding )
        location   = VALUE #(
          object   = VALUE #( type = 'PROG' name = ls_finding-include )
          position = VALUE #( line = ls_finding-line column = lv_column ) )
        parameters = VALUE #( param_1 = ls_finding-text ) ) INTO TABLE rt_findings.
    ENDLOOP.
  ENDMETHOD.

  METHOD to_code.
    IF is_finding-code = zcl_lnt_utils=>c_code-dump.
      rv_code = zcl_lnt_atc_meta_data=>c_code-dump.
      RETURN.
    ENDIF.

    CASE is_finding-kind.
      WHEN zcl_lnt_utils=>c_kind-error.
        rv_code = zcl_lnt_atc_meta_data=>c_code-error.
      WHEN zcl_lnt_utils=>c_kind-note.
        rv_code = zcl_lnt_atc_meta_data=>c_code-info.
      WHEN OTHERS.
        rv_code = zcl_lnt_atc_meta_data=>c_code-warning.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.
