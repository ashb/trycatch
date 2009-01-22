#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "hook_op_check.h"
#include "hook_op_ppaddr.h"

STATIC OP* unwind_return (pTHX_ OP *op, void *user_data) {
  dSP;
  SV* ctx;
  CV *unwind;

  printf("unwind_return\n");
  op_dump(op);
  PERL_UNUSED_VAR(user_data);
  //sv_dump(TOPs);

  ENTER;
  PUSHMARK(SP);
  XPUSHs(sv_2mortal(newSViv(2)));
  PUTBACK;

  call_pv("Scope::Upper::CALLER", G_SCALAR);

  SPAGAIN;

  // I probably dont need to POP,inc then push
  ctx = POPs;
  SvREFCNT_inc(ctx);


  // call_pv("Scope::Upper::unwind", G_VOID);
  // Can't use call_sv et al. since it resets PL_op.
 
  unwind = get_cv("Scope::Upper::unwind", 0);
  XPUSHs(ctx);
  XPUSHs( (SV*)unwind);

  CALL_FPTR(PL_ppaddr[OP_ENTERSUB])(aTHX);
  
  SvREFCNT_dec(ctx);
  printf("final PL_op:\n");
  op_dump(PL_op);
  return PL_op->op_next;
}

STATIC OP* check_return (pTHX_ OP *op, void *user_data) {
  PERL_UNUSED_VAR(user_data);

  hook_op_ppaddr(op, unwind_return, NULL);
  printf("return op checked\n");
  return op;
}

MODULE = TryCatch PACKAGE = TryCatch::XS

void
call_in_context(code, array_ctx, eval)
SV* code;
SV* array_ctx; // Desired wantarray context;
SV*  eval;
  PROTOTYPE: DISABLE
  PPCODE:
    int ret, ctx;

    ctx =  SvTRUE(array_ctx) ? G_ARRAY :
           array_ctx != &PL_sv_undef ? G_SCALAR: G_VOID;
    if (SvTRUE(eval))
      ctx |= G_EVAL;

    ret = call_sv(code, ctx);
  
    SPAGAIN;

    if ( (ctx & G_EVAL) && SvTRUE(ERRSV)) {
      while (ret) {
        POPs;
        ret--;
      }
      XPUSHs(&PL_sv_no);
      XSRETURN(1);
    }

    XPUSHs(&PL_sv_no);
    XSRETURN(1+ret);

UV 
install_return_op_check()
  CODE:
    RETVAL = hook_op_check( OP_RETURN, check_return, NULL);
  OUTPUT:
    RETVAL

void
uninstall_return_op_check(id)
UV id
  CODE:
    hook_op_check_remove(OP_RETURN, id);
  OUTPUT:
