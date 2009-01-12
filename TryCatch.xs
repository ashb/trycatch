#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define MY_CXT_KEY "TryCatch::XS::_guts" XS_VERSION

typedef struct {
  int prev_op_is_return;
  runops_proc_t old_runops;
} my_cxt_t;

START_MY_CXT

static int
my_runops(pTHX)
{
  OPCODE prev_opcode = OP_NULL;
#ifdef PERL_IMPLICIT_CONTEXT
  dMY_CXT;
#else
  dMY_CXT_INTERP(pTHX);
#endif

  while ((PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX))) {
    PERL_ASYNC_CHECK();
    prev_opcode = PL_op->op_type;
  }
  MY_CXT.prev_op_is_return = prev_opcode==OP_RETURN;
  TAINT_NOT;
  return 0;
}


MODULE = TryCatch PACKAGE = TryCatch::XS


BOOT:
{
  MY_CXT_INIT;
  MY_CXT.prev_op_is_return = 0;
}

void
_monitor_return(code, array_ctx)
SV* code;
SV* array_ctx; // Desired wantarray context;
  PROTOTYPE: DISABLE
  PREINIT:
    dMY_CXT;
  PPCODE:
    int ret, ctx;

    MY_CXT.old_runops = PL_runops;
    MY_CXT.prev_op_is_return = 0;
    PL_runops = &my_runops;

    ctx =  SvTRUE(array_ctx) ? G_ARRAY :
           array_ctx != &PL_sv_undef ? G_SCALAR: G_VOID;

    ret = call_sv(code, ctx);
  
    SPAGAIN;
    PL_runops = MY_CXT.old_runops;
    XPUSHs(MY_CXT.prev_op_is_return ? &PL_sv_yes : &PL_sv_no);
    XSRETURN(1+ret);

void
CLONE(...)
    CODE:
    MY_CXT_CLONE;

