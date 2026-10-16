CLASS zlnt_runtime_tele_970d5104e5f4 DEFINITION PUBLIC CREATE PRIVATE.
  PUBLIC SECTION.
    CLASS-METHODS now RETURNING VALUE(result) TYPE f.
  PROTECTED SECTION.
  PRIVATE SECTION.
    CLASS-DATA initialized TYPE abap_bool.
    CLASS-DATA previous TYPE utclong.
    CLASS-DATA elapsed TYPE decfloat34.
ENDCLASS.
CLASS zlnt_runtime_tele_970d5104e5f4 IMPLEMENTATION.
  METHOD now.
    DATA(current) = utclong_current( ).
    IF initialized = abap_false.
      initialized = abap_true.
      previous = current.
    ELSE.
      DATA(delta) = utclong_diff( high = current low = previous ).
      IF delta > 0.
        elapsed = elapsed + delta.
      ENDIF.
      previous = current.
    ENDIF.
    result = trunc( elapsed * 1000 ).
  ENDMETHOD.
ENDCLASS.
