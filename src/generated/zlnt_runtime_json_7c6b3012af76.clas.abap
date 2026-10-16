CLASS zlnt_runtime_json_7c6b3012af76 DEFINITION PUBLIC CREATE PRIVATE.
  PUBLIC SECTION.
    CLASS-METHODS parse IMPORTING p0 TYPE string RETURNING VALUE(result) TYPE REF TO zlnt_runtime_dyna_a429568d5be8.
  PROTECTED SECTION.
  PRIVATE SECTION.
    DATA input TYPE string.
    DATA cursor TYPE i.
    METHODS whitespace.
    METHODS value RETURNING VALUE(result) TYPE REF TO zlnt_runtime_dyna_a429568d5be8.
    METHODS text RETURNING VALUE(result) TYPE string.
    METHODS hex RETURNING VALUE(result) TYPE i.
    METHODS unicode_unit IMPORTING p0 TYPE i RETURNING VALUE(result) TYPE string.
ENDCLASS.
CLASS zlnt_runtime_json_7c6b3012af76 IMPLEMENTATION.
  METHOD parse.
    DATA parser TYPE REF TO zlnt_runtime_json_7c6b3012af76.
    CREATE OBJECT parser.
    parser->input = p0.
    result = parser->value( ).
    parser->whitespace( ).
    IF parser->cursor <> strlen( p0 ).
      RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
    ENDIF.
  ENDMETHOD.

  METHOD whitespace.
    DATA ch TYPE c LENGTH 1.
    DATA cr TYPE c LENGTH 1.
    cr = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( `000D` ) ).
    WHILE cursor < strlen( input ).
      ch = input+cursor(1).
      IF ch <> space AND ch <> cr AND ch <> cl_abap_char_utilities=>newline AND ch <> cl_abap_char_utilities=>horizontal_tab.
        EXIT.
      ENDIF.
      cursor = cursor + 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD hex.
    DATA ch TYPE c LENGTH 1.
    DATA digit TYPE i.
    DATA alphabet TYPE string VALUE '0123456789abcdef'.
    DO 4 TIMES.
      IF cursor >= strlen( input ).
        RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
      ENDIF.
      ch = to_lower( input+cursor(1) ).
      FIND ch IN alphabet MATCH OFFSET digit.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
      ENDIF.
      result = result * 16 + digit.
      cursor = cursor + 1.
    ENDDO.
  ENDMETHOD.

  METHOD text.
    DATA ch TYPE string.
    DATA code TYPE i.
    DATA low TYPE i.
    DATA pair TYPE string.
    DATA bytes TYPE xstring.
    DATA unit TYPE x LENGTH 2.
    DATA converter TYPE REF TO if_abap_conv_in.
    cursor = cursor + 1.
    WHILE cursor < strlen( input ).
      ch = input+cursor(1).
      cursor = cursor + 1.
      IF ch = '"'.
        RETURN.
      ENDIF.
      IF ch = '\'.
        IF cursor >= strlen( input ).
          RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
        ENDIF.
        ch = input+cursor(1).
        cursor = cursor + 1.
        CASE ch.
          WHEN '"' OR '\' OR '/'.
          WHEN 'b'.
            ch = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( `0008` ) ).
          WHEN 'f'.
            ch = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( `000C` ) ).
          WHEN 'n'.
            ch = cl_abap_char_utilities=>newline.
          WHEN 'r'.
            ch = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( `000D` ) ).
          WHEN 't'.
            ch = cl_abap_char_utilities=>horizontal_tab.
          WHEN 'u'.
            code = hex( ).
            IF code >= 55296 AND code <= 56319 AND cursor + 6 <= strlen( input ).
              pair = input+cursor(2).
              IF pair = '\u'.
                cursor = cursor + 2.
                low = hex( ).
                IF low >= 56320 AND low <= 57343.
                  unit = code.
                  CONCATENATE unit+1(1) unit+0(1) INTO bytes IN BYTE MODE.
                  unit = low.
                  CONCATENATE bytes unit+1(1) unit+0(1) INTO bytes IN BYTE MODE.
                  converter = cl_abap_conv_codepage=>create_in( codepage = `UTF-16LE` ).
                  ch = converter->convert( bytes ).
                ELSE.
                  cursor = cursor - 6.
                  ch = unicode_unit( code ).
                ENDIF.
              ELSE.
                unit = code.
                ch = unicode_unit( code ).
              ENDIF.
            ELSEIF code >= 55296 AND code <= 57343.
              unit = code.
              ch = unicode_unit( code ).
            ELSE.
              DATA zlnt_conv_1 TYPE x LENGTH 2.
              zlnt_conv_1 = code.
              ch = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( zlnt_conv_1 ) ).
            ENDIF.
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
        ENDCASE.
      ELSE.
        DATA(zlnt_conv_3) = cl_abap_conv_codepage=>create_out( codepage = `UTF-16LE` )->convert( COND string( WHEN ch IS INITIAL THEN ` ` ELSE ch ) ).
        DATA zlnt_conv_3_low TYPE i.
        zlnt_conv_3_low = zlnt_conv_3(1).
        code = zlnt_conv_3+1(1).
        code = code * 256 + zlnt_conv_3_low.
        IF code < 32.
          RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
        ENDIF.
      ENDIF.
      CONCATENATE result ch INTO result RESPECTING BLANKS.
    ENDWHILE.
    RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
  ENDMETHOD.

  METHOD value.
    DATA ch TYPE string.
    DATA key TYPE string.
    DATA child TYPE REF TO zlnt_runtime_dyna_a429568d5be8.
    DATA start TYPE i.
    DATA count TYPE i.
    DATA token TYPE string.
    whitespace( ).
    IF cursor >= strlen( input ).
      RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
    ENDIF.
    ch = input+cursor(1).
    CREATE OBJECT result.
    CASE ch.
      WHEN '"'.
        result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_string.
        result->sval = text( ).
      WHEN '{'.
        result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_object.
        cursor = cursor + 1.
        whitespace( ).
        IF cursor < strlen( input ) AND input+cursor(1) = '}'.
          cursor = cursor + 1.
          RETURN.
        ENDIF.
        WHILE cursor < strlen( input ).
          IF input+cursor(1) <> '"'.
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          key = text( ).
          whitespace( ).
          IF cursor >= strlen( input ) OR input+cursor(1) <> ':'.
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          cursor = cursor + 1.
          child = value( ).
          result->put( p0 = key p1 = child ).
          whitespace( ).
          IF cursor >= strlen( input ).
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          ch = input+cursor(1).
          cursor = cursor + 1.
          IF ch = '}'.
            RETURN.
          ELSEIF ch <> ','.
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          whitespace( ).
        ENDWHILE.
        RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
      WHEN '['.
        result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_array.
        cursor = cursor + 1.
        whitespace( ).
        IF cursor < strlen( input ) AND input+cursor(1) = ']'.
          cursor = cursor + 1.
          RETURN.
        ENDIF.
        WHILE cursor < strlen( input ).
          child = value( ).
          result->append( child ).
          whitespace( ).
          IF cursor >= strlen( input ).
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          ch = input+cursor(1).
          cursor = cursor + 1.
          IF ch = ']'.
            RETURN.
          ELSEIF ch <> ','.
            RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
          ENDIF.
          whitespace( ).
        ENDWHILE.
        RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
      WHEN OTHERS.
        start = cursor.
        WHILE cursor < strlen( input ).
          ch = input+cursor(1).
          IF ch = ',' OR ch = '}' OR ch = ']' OR ch = ` ` OR ch = cl_abap_char_utilities=>newline OR ch = cl_abap_char_utilities=>horizontal_tab OR ch = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( `000D` ) ).
            EXIT.
          ENDIF.
          cursor = cursor + 1.
        ENDWHILE.
        count = cursor - start.
        token = input+start(count).
        CASE token.
          WHEN 'null'.
            result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_null.
          WHEN 'true' OR 'false'.
            result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_boolean.
            IF token = 'true'.
              result->bval = abap_true.
            ELSE.
              result->bval = abap_false.
            ENDIF.
          WHEN OTHERS.
            FIND REGEX '^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?$' IN token.
            IF sy-subrc <> 0.
              RAISE EXCEPTION TYPE zlnt_exception_js_ebcc2df7d5e4.
            ENDIF.
            result->tag = zlnt_runtime_dyna_a429568d5be8=>tag_number.
            TRY.
                result->nval = token.
              CATCH cx_sy_conversion_error cx_sy_arithmetic_error.
                RAISE EXCEPTION TYPE zlnt_exception_re_478ac52845e5.
            ENDTRY.
        ENDCASE.
    ENDCASE.
  ENDMETHOD.

  METHOD unicode_unit.
    DATA unit TYPE x LENGTH 2.
    DATA padding TYPE x LENGTH 2.
    DATA bytes TYPE xstring.
    DATA converter TYPE REF TO if_abap_conv_in.
    IF p0 < 55296 OR p0 > 57343.
      DATA zlnt_conv_2 TYPE x LENGTH 2.
      zlnt_conv_2 = p0.
      result = cl_abap_conv_codepage=>create_in( codepage = `UTF-16BE` )->convert( CONV xstring( zlnt_conv_2 ) ).
      RETURN.
    ENDIF.
    unit = p0.
    CONCATENATE unit+1(1) unit+0(1) INTO bytes IN BYTE MODE.
    IF p0 < 56320.
      padding = '00DC'.
      CONCATENATE bytes padding INTO bytes IN BYTE MODE.
    ELSE.
      padding = '00D8'.
      CONCATENATE padding bytes INTO bytes IN BYTE MODE.
    ENDIF.
    converter = cl_abap_conv_codepage=>create_in( codepage = `UTF-16LE` ).
    result = converter->convert( bytes ).
    IF p0 < 56320.
      result = result+0(1).
    ELSE.
      result = result+1(1).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
