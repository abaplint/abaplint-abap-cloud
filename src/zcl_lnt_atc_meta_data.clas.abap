CLASS zcl_lnt_atc_meta_data DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_ci_atc_check_meta_data.

    CONSTANTS:
      BEGIN OF c_code,
        error   TYPE if_ci_atc_check=>ty_finding_code VALUE 'ERROR',
        warning TYPE if_ci_atc_check=>ty_finding_code VALUE 'WARNING',
        info    TYPE if_ci_atc_check=>ty_finding_code VALUE 'INFO',
        dump    TYPE if_ci_atc_check=>ty_finding_code VALUE 'DUMP',
      END OF c_code.

    "! @parameter iv_pseudo_comment | Without the leading "#EC, like CI_SUBRC
    METHODS constructor
      IMPORTING
        iv_title          TYPE string
        iv_pseudo_comment TYPE string OPTIONAL.

  PRIVATE SECTION.
    DATA mv_title TYPE string.
    DATA mv_pseudo_comment TYPE string.
ENDCLASS.

CLASS zcl_lnt_atc_meta_data IMPLEMENTATION.
  METHOD constructor.
    mv_title = iv_title.
    mv_pseudo_comment = iv_pseudo_comment.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~get_description.
    description = |abaplint - { mv_title }|.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~get_checked_object_types.
    LOOP AT zcl_lnt_utils=>object_types( ) INTO DATA(lv_type).
      INSERT lv_type INTO TABLE types.
    ENDLOOP.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~get_finding_code_infos.
* ATC sets the severity per finding code, so there is one code per abaplint severity
    finding_code_infos = VALUE #(
      ( code           = c_code-error
        severity       = if_ci_atc_check=>finding_severities-error
        text           = '&1'
        pseudo_comment = mv_pseudo_comment )
      ( code           = c_code-warning
        severity       = if_ci_atc_check=>finding_severities-warning
        text           = '&1'
        pseudo_comment = mv_pseudo_comment )
      ( code           = c_code-info
        severity       = if_ci_atc_check=>finding_severities-note
        text           = '&1'
        pseudo_comment = mv_pseudo_comment )
      ( code     = c_code-dump
        severity = if_ci_atc_check=>finding_severities-error
        text     = 'abaplint failed: &1' ) ).
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~get_quickfix_code_infos.
    CLEAR quickfix_code_infos.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~get_attributes.
    CLEAR attributes.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~is_remote_enabled.
* the source is read with the ATC code provider, which also works for remote systems
    is_remote_enabled = abap_true.
  ENDMETHOD.

  METHOD if_ci_atc_check_meta_data~uses_checksums.
    uses_checksums = abap_false.
  ENDMETHOD.
ENDCLASS.
