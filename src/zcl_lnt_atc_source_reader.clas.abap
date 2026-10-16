* Reads objects as abapGit style files from the ATC code provider. The released API gives
* statements and tokens, but no comments and no source lines, so each include is rebuilt by
* placing the lexemes at their token positions. The class layout follows
* ZCL_ABAPGIT_OO_SERIALIZER, https://github.com/abapGit/abapGit, MIT License
CLASS zcl_lnt_atc_source_reader DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES zif_lnt_source_reader.

    TYPES:
      BEGIN OF ty_include_source,
        include TYPE zif_lnt_source_reader=>ty_include,
        source  TYPE string_table,
      END OF ty_include_source,
      ty_include_sources TYPE SORTED TABLE OF ty_include_source WITH UNIQUE KEY include.

    "! Column of the first character in a line, as given in the token positions
    CONSTANTS c_first_column TYPE i VALUE 0.

    METHODS constructor
      IMPORTING
        ii_code_provider TYPE REF TO if_ci_atc_source_code_provider.

    "! Rebuilds the source of each include from its statements
    CLASS-METHODS build_includes
      IMPORTING
        it_statements      TYPE if_ci_atc_source_code_provider=>ty_statements
      RETURNING
        VALUE(rt_includes) TYPE ty_include_sources.

    "! Assembles the includes of an object into abapGit style files
    CLASS-METHODS build_files
      IMPORTING
        iv_object_type TYPE csequence
        iv_object_name TYPE csequence
        it_includes    TYPE ty_include_sources
      EXPORTING
        et_files       TYPE zif_lnt_source_reader=>ty_files
        et_line_map    TYPE zif_lnt_source_reader=>ty_line_maps.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_piece,
        include TYPE zif_lnt_source_reader=>ty_include,
        line    TYPE i,
        column  TYPE i,
        text    TYPE string,
      END OF ty_piece,
      ty_pieces TYPE STANDARD TABLE OF ty_piece WITH EMPTY KEY.
    TYPES:
      BEGIN OF ty_sorted_statement,
        include TYPE zif_lnt_source_reader=>ty_include,
        line    TYPE i,
        column  TYPE i,
        index   TYPE i,
      END OF ty_sorted_statement,
      ty_sorted_statements TYPE SORTED TABLE OF ty_sorted_statement WITH NON-UNIQUE KEY include line column index.

    CONSTANTS:
      BEGIN OF c_include,
        locals_def  TYPE c LENGTH 5 VALUE 'CCDEF',
        locals_imp  TYPE c LENGTH 5 VALUE 'CCIMP',
        macros      TYPE c LENGTH 5 VALUE 'CCMAC',
        testclasses TYPE c LENGTH 5 VALUE 'CCAU',
        public      TYPE c LENGTH 5 VALUE 'CU',
        protected   TYPE c LENGTH 5 VALUE 'CO',
        private     TYPE c LENGTH 5 VALUE 'CI',
        method      TYPE c LENGTH 5 VALUE 'CM',
        interface   TYPE c LENGTH 5 VALUE 'IU',
      END OF c_include.

    DATA mi_code_provider TYPE REF TO if_ci_atc_source_code_provider.

    CLASS-METHODS shared_tokens
      IMPORTING
        is_previous     TYPE if_ci_atc_source_code_provider=>ty_statement
        is_statement    TYPE if_ci_atc_source_code_provider=>ty_statement
      RETURNING
        VALUE(rv_count) TYPE i.

    CLASS-METHODS pseudo_comment_name
      IMPORTING
        iv_pseudo_comment TYPE string
      RETURNING
        VALUE(rv_name)    TYPE string.

    CLASS-METHODS end_column
      IMPORTING
        is_token         TYPE if_ci_atc_source_code_provider=>ty_token
      RETURNING
        VALUE(rv_column) TYPE i.

    CLASS-METHODS render
      IMPORTING
        it_pieces        TYPE ty_pieces
      RETURNING
        VALUE(rt_source) TYPE string_table.

    CLASS-METHODS build_clas
      IMPORTING
        iv_name     TYPE csequence
        it_includes TYPE ty_include_sources
      CHANGING
        ct_files    TYPE zif_lnt_source_reader=>ty_files
        ct_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    CLASS-METHODS build_fugr
      IMPORTING
        iv_name     TYPE csequence
        it_includes TYPE ty_include_sources
      CHANGING
        ct_files    TYPE zif_lnt_source_reader=>ty_files
        ct_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    "! Adds the include as a file of its own, if it exists
    CLASS-METHODS add_include
      IMPORTING
        iv_filename TYPE string
        iv_include  TYPE csequence
        it_includes TYPE ty_include_sources
      CHANGING
        ct_files    TYPE zif_lnt_source_reader=>ty_files
        ct_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    "! Appends the include to a file being assembled, if it exists
    CLASS-METHODS append_include
      IMPORTING
        iv_filename TYPE string
        iv_include  TYPE csequence
        it_includes TYPE ty_include_sources
      CHANGING
        ct_source   TYPE string_table
        ct_line_map TYPE zif_lnt_source_reader=>ty_line_maps.

    CLASS-METHODS to_filename
      IMPORTING
        iv_name            TYPE csequence
        iv_extension       TYPE csequence
      RETURNING
        VALUE(rv_filename) TYPE string.

    CLASS-METHODS class_include
      IMPORTING
        iv_class_name     TYPE csequence
        iv_suffix         TYPE csequence
      RETURNING
        VALUE(rv_include) TYPE zif_lnt_source_reader=>ty_include.
ENDCLASS.

CLASS zcl_lnt_atc_source_reader IMPLEMENTATION.
  METHOD constructor.
    mi_code_provider = ii_code_provider.
  ENDMETHOD.

  METHOD zif_lnt_source_reader~read.
    DATA lt_statements TYPE if_ci_atc_source_code_provider=>ty_statements.
    DATA lr_procedures TYPE REF TO if_ci_atc_source_code_provider=>ty_procedures.
    FIELD-SYMBOLS <lt_procedures> TYPE if_ci_atc_source_code_provider=>ty_procedures.

    CLEAR et_files.
    CLEAR et_line_map.

    IF mi_code_provider IS NOT BOUND.
      RETURN.
    ENDIF.

    DATA(ls_unit) = mi_code_provider->object_to_comp_unit( VALUE #(
      type = iv_object_type
      name = iv_object_name ) ).
* the released API raises cx_ci_atc_invalid_comp_unit, a cx_dynamic_check, open-abap-ci declares cx_static_check
    TRY.
        lr_procedures = mi_code_provider->get_procedures( ls_unit ).
      CATCH cx_root.
        RETURN.
    ENDTRY.
    IF lr_procedures IS NOT BOUND.
      RETURN.
    ENDIF.

    ASSIGN lr_procedures->* TO <lt_procedures>.
    LOOP AT <lt_procedures> INTO DATA(ls_procedure).
      INSERT LINES OF ls_procedure-statements INTO TABLE lt_statements.
    ENDLOOP.

    build_files(
      EXPORTING
        iv_object_type = iv_object_type
        iv_object_name = iv_object_name
        it_includes    = build_includes( lt_statements )
      IMPORTING
        et_files       = et_files
        et_line_map    = et_line_map ).
  ENDMETHOD.

  METHOD build_includes.
    DATA lt_sorted TYPE ty_sorted_statements.
    DATA lt_pieces TYPE ty_pieces.
    DATA lt_group TYPE ty_pieces.
    DATA ls_previous TYPE if_ci_atc_source_code_provider=>ty_statement.
    DATA lv_terminator TYPE i.
    DATA lv_include TYPE zif_lnt_source_reader=>ty_include.

* the statements come per procedure, sort them by the position of their last token. The parts of a
* chained statement share the tokens before the colon, so their first tokens have the same position
    LOOP AT it_statements INTO DATA(ls_statement).
      DATA(lv_index) = sy-tabix.
      DATA(lv_last) = lines( ls_statement-tokens ).
      IF lv_last = 0.
        CONTINUE.
      ENDIF.
      READ TABLE ls_statement-tokens INDEX lv_last INTO DATA(ls_last).
      INSERT VALUE #(
        include = ls_statement-include
        line    = ls_last-position-line
        column  = ls_last-position-column
        index   = lv_index ) INTO TABLE lt_sorted.
    ENDLOOP.

    LOOP AT lt_sorted INTO DATA(ls_sorted).
      READ TABLE it_statements INDEX ls_sorted-index INTO ls_statement.

      DATA(lv_shared) = 0.
      IF lv_include = ls_statement-include.
        lv_shared = shared_tokens(
          is_previous  = ls_previous
          is_statement = ls_statement ).
      ENDIF.
      IF lv_shared >= lines( ls_statement-tokens ).
* the same statement given twice
        CONTINUE.
      ELSEIF lv_shared > 0.
* continues a chain, the previous part ends with a comma, the colon follows the shared tokens
        READ TABLE lt_pieces INDEX lv_terminator ASSIGNING FIELD-SYMBOL(<ls_terminator>).
        <ls_terminator>-text = `,`.
        READ TABLE ls_statement-tokens INDEX lv_shared INTO DATA(ls_head).
        DATA(lv_colon_line) = ls_head-position-line.
        DATA(lv_colon_column) = end_column( ls_head ).
        READ TABLE lt_pieces TRANSPORTING NO FIELDS WITH KEY
          include = ls_statement-include
          line    = lv_colon_line
          column  = lv_colon_column
          text    = `:`.
        IF sy-subrc <> 0.
          INSERT VALUE #(
            include = ls_statement-include
            line    = lv_colon_line
            column  = lv_colon_column
            text    = `:` ) INTO TABLE lt_pieces.
        ENDIF.
      ENDIF.

      DATA(lv_from) = lv_shared + 1.
      LOOP AT ls_statement-tokens INTO DATA(ls_token) FROM lv_from.
        INSERT VALUE #(
          include = ls_statement-include
          line    = ls_token-position-line
          column  = ls_token-position-column - c_first_column
          text    = ls_token-lexeme ) INTO TABLE lt_pieces.
      ENDLOOP.

      INSERT VALUE #(
        include = ls_statement-include
        line    = ls_token-position-line
        column  = end_column( ls_token )
        text    = `.` ) INTO TABLE lt_pieces.
      lv_terminator = lines( lt_pieces ).

* pseudo comments end the line, the column is past any other piece on the line
      LOOP AT ls_statement-pseudo_comments INTO DATA(lv_pseudo).
        INSERT VALUE #(
          include = ls_statement-include
          line    = ls_token-position-line
          column  = 10000
          text    = |"#EC { pseudo_comment_name( lv_pseudo ) }| ) INTO TABLE lt_pieces.
      ENDLOOP.

      ls_previous = ls_statement.
      lv_include = ls_statement-include.
    ENDLOOP.

    SORT lt_pieces BY include line column.
    CLEAR lv_include.
    LOOP AT lt_pieces INTO DATA(ls_piece).
      IF ls_piece-include <> lv_include AND lt_group IS NOT INITIAL.
        INSERT VALUE #( include = lv_include source = render( lt_group ) ) INTO TABLE rt_includes.
        CLEAR lt_group.
      ENDIF.
      lv_include = ls_piece-include.
      INSERT ls_piece INTO TABLE lt_group.
    ENDLOOP.
    IF lt_group IS NOT INITIAL.
      INSERT VALUE #( include = lv_include source = render( lt_group ) ) INTO TABLE rt_includes.
    ENDIF.
  ENDMETHOD.

  METHOD pseudo_comment_name.
* the pseudo comments may be given with or without the leading "#EC
    rv_name = condense( iv_pseudo_comment ).
    rv_name = shift_left( val = rv_name sub = `"` ).
    rv_name = shift_left( val = rv_name sub = `#` ).
    IF to_upper( rv_name ) CP 'EC *'.
      rv_name = condense( substring( val = rv_name off = 2 ) ).
    ENDIF.
  ENDMETHOD.

  METHOD shared_tokens.
    LOOP AT is_statement-tokens INTO DATA(ls_token).
      DATA(lv_index) = sy-tabix.
      READ TABLE is_previous-tokens INDEX lv_index INTO DATA(ls_previous).
      IF sy-subrc <> 0
          OR ls_previous-lexeme <> ls_token-lexeme
          OR ls_previous-position <> ls_token-position.
        RETURN.
      ENDIF.
      rv_count = lv_index.
    ENDLOOP.
  ENDMETHOD.

  METHOD end_column.
    rv_column = is_token-position-column - c_first_column + strlen( is_token-lexeme ).
  ENDMETHOD.

  METHOD render.
    DATA lv_line TYPE string.

    LOOP AT it_pieces INTO DATA(ls_piece).
      WHILE lines( rt_source ) < ls_piece-line.
        INSERT `` INTO TABLE rt_source.
      ENDWHILE.
      READ TABLE rt_source INDEX ls_piece-line INTO lv_line.

      DATA(lv_length) = strlen( lv_line ).
      IF lv_length < ls_piece-column AND ls_piece-column < 10000.
        lv_line = lv_line && repeat( val = ` ` occ = ls_piece-column - lv_length ).
      ELSEIF lv_length > 0 AND ( lv_length > ls_piece-column OR ls_piece-column >= 10000 )
          AND ls_piece-text <> `.` AND ls_piece-text <> `,` AND ls_piece-text <> `:`.
* overlapping pieces, or a pseudo comment, keep them apart
        lv_line = lv_line && ` `.
      ENDIF.
      lv_line = lv_line && ls_piece-text.

      MODIFY rt_source INDEX ls_piece-line FROM lv_line.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_files.
    CLEAR et_files.
    CLEAR et_line_map.

    CASE iv_object_type.
      WHEN 'PROG'.
        add_include(
          EXPORTING
            iv_filename = to_filename( iv_name = iv_object_name iv_extension = 'prog.abap' )
            iv_include  = to_upper( iv_object_name )
            it_includes = it_includes
          CHANGING
            ct_files    = et_files
            ct_line_map = et_line_map ).
      WHEN 'CLAS'.
        build_clas(
          EXPORTING
            iv_name     = iv_object_name
            it_includes = it_includes
          CHANGING
            ct_files    = et_files
            ct_line_map = et_line_map ).
      WHEN 'INTF'.
        add_include(
          EXPORTING
            iv_filename = to_filename( iv_name = iv_object_name iv_extension = 'intf.abap' )
            iv_include  = class_include( iv_class_name = iv_object_name iv_suffix = c_include-interface )
            it_includes = it_includes
          CHANGING
            ct_files    = et_files
            ct_line_map = et_line_map ).
      WHEN 'FUGR'.
        build_fugr(
          EXPORTING
            iv_name     = iv_object_name
            it_includes = it_includes
          CHANGING
            ct_files    = et_files
            ct_line_map = et_line_map ).
    ENDCASE.
  ENDMETHOD.

  METHOD build_clas.
* the definition and the method implementations are assembled into one file. The ENDCLASS and
* CLASS IMPLEMENTATION statements are in the class pool include, they are added here and not mapped
    DATA lt_source TYPE string_table.

    DATA(lv_filename) = to_filename( iv_name = iv_name iv_extension = 'clas.abap' ).
    DATA(lv_name) = to_lower( iv_name ).

    append_include(
      EXPORTING
        iv_filename = lv_filename
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-public )
        it_includes = it_includes
      CHANGING
        ct_source   = lt_source
        ct_line_map = ct_line_map ).
    IF lt_source IS INITIAL.
      RETURN.
    ENDIF.
    append_include(
      EXPORTING
        iv_filename = lv_filename
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-protected )
        it_includes = it_includes
      CHANGING
        ct_source   = lt_source
        ct_line_map = ct_line_map ).
    append_include(
      EXPORTING
        iv_filename = lv_filename
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-private )
        it_includes = it_includes
      CHANGING
        ct_source   = lt_source
        ct_line_map = ct_line_map ).
    INSERT `ENDCLASS.` INTO TABLE lt_source.
    INSERT `` INTO TABLE lt_source.
    INSERT |CLASS { lv_name } IMPLEMENTATION.| INTO TABLE lt_source.

    DATA(lv_methods) = class_include( iv_class_name = iv_name iv_suffix = c_include-method ).
    LOOP AT it_includes INTO DATA(ls_include) WHERE include CP |{ lv_methods }*|.
      append_include(
        EXPORTING
          iv_filename = lv_filename
          iv_include  = ls_include-include
          it_includes = it_includes
        CHANGING
          ct_source   = lt_source
          ct_line_map = ct_line_map ).
      INSERT `` INTO TABLE lt_source.
    ENDLOOP.
    INSERT `ENDCLASS.` INTO TABLE lt_source.

    INSERT VALUE #( filename = lv_filename source = lt_source ) INTO TABLE ct_files.

    add_include(
      EXPORTING
        iv_filename = to_filename( iv_name = iv_name iv_extension = 'clas.locals_def.abap' )
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-locals_def )
        it_includes = it_includes
      CHANGING
        ct_files    = ct_files
        ct_line_map = ct_line_map ).
    add_include(
      EXPORTING
        iv_filename = to_filename( iv_name = iv_name iv_extension = 'clas.locals_imp.abap' )
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-locals_imp )
        it_includes = it_includes
      CHANGING
        ct_files    = ct_files
        ct_line_map = ct_line_map ).
    add_include(
      EXPORTING
        iv_filename = to_filename( iv_name = iv_name iv_extension = 'clas.macros.abap' )
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-macros )
        it_includes = it_includes
      CHANGING
        ct_files    = ct_files
        ct_line_map = ct_line_map ).
    add_include(
      EXPORTING
        iv_filename = to_filename( iv_name = iv_name iv_extension = 'clas.testclasses.abap' )
        iv_include  = class_include( iv_class_name = iv_name iv_suffix = c_include-testclasses )
        it_includes = it_includes
      CHANGING
        ct_files    = ct_files
        ct_line_map = ct_line_map ).
  ENDMETHOD.

  METHOD build_fugr.
* the main program first, then the other includes of the group, like LZFOOTOP and LZFOOU01
    DATA lv_namespace TYPE string.
    DATA lv_group TYPE string.

    lv_group = to_upper( iv_name ).
    IF lv_group CP '/*/*'.
      lv_namespace = substring_before( val = lv_group sub = '/' occ = 2 ) && '/'.
      lv_group = substring_after( val = lv_group sub = '/' occ = 2 ).
    ENDIF.

    DATA(lv_main) = |{ lv_namespace }SAPL{ lv_group }|.
    DATA(lv_prefix) = |{ lv_namespace }L{ lv_group }|.

    add_include(
      EXPORTING
        iv_filename = to_filename( iv_name = iv_name iv_extension = |fugr.{ to_filename( iv_name = lv_main iv_extension = 'abap' ) }| )
        iv_include  = lv_main
        it_includes = it_includes
      CHANGING
        ct_files    = ct_files
        ct_line_map = ct_line_map ).
    LOOP AT it_includes INTO DATA(ls_include) WHERE include CP |{ lv_prefix }*|.
      add_include(
        EXPORTING
          iv_filename = to_filename( iv_name = iv_name iv_extension = |fugr.{ to_filename( iv_name = ls_include-include iv_extension = 'abap' ) }| )
          iv_include  = ls_include-include
          it_includes = it_includes
        CHANGING
          ct_files    = ct_files
          ct_line_map = ct_line_map ).
    ENDLOOP.
  ENDMETHOD.

  METHOD add_include.
    READ TABLE it_includes WITH TABLE KEY include = iv_include INTO DATA(ls_include).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    INSERT VALUE #(
      filename = iv_filename
      source   = ls_include-source ) INTO TABLE ct_files.
    INSERT VALUE #(
      filename  = iv_filename
      from_row  = 1
      to_row    = lines( ls_include-source )
      include   = iv_include
      first_row = 1 ) INTO TABLE ct_line_map.
  ENDMETHOD.

  METHOD append_include.
    READ TABLE it_includes WITH TABLE KEY include = iv_include INTO DATA(ls_include).
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    INSERT VALUE #(
      filename  = iv_filename
      from_row  = lines( ct_source ) + 1
      to_row    = lines( ct_source ) + lines( ls_include-source )
      include   = iv_include
      first_row = 1 ) INTO TABLE ct_line_map.
    INSERT LINES OF ls_include-source INTO TABLE ct_source.
  ENDMETHOD.

  METHOD to_filename.
    rv_filename = replace(
      val  = to_lower( iv_name )
      sub  = '/'
      with = '#'
      occ  = 0 ).
    rv_filename = |{ rv_filename }.{ iv_extension }|.
  ENDMETHOD.

  METHOD class_include.
    DATA lv_root TYPE c LENGTH 30.

    lv_root = to_upper( iv_class_name ).
    TRANSLATE lv_root USING ' ='.
    rv_include = |{ lv_root }{ iv_suffix }|.
  ENDMETHOD.
ENDCLASS.
