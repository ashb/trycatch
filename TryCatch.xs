#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_sv_2pv_flags
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_ppaddr.h"

static int trycatch_debug = 0;

STATIC I32
dump_cxstack()
{
  I32 i;
  for (i = cxstack_ix; i >= 0; i--) {
    register const PERL_CONTEXT * const cx = cxstack+i;
    switch (CxTYPE(cx)) {
    default:
        continue;
    case CXt_EVAL:
        printf("***\n* cx stack %d: WA: %d\n", (int)i, cx->blk_gimme);
        sv_dump((SV*)cx->blk_eval.cv);
        break;
    case CXt_SUB:
        printf("***\n* cx stack %d: WA: %d\n", (int)i, cx->blk_gimme);
        sv_dump((SV*)cx->blk_sub.cv);
        break;
    }
  }
  return i;
}

// Return the (array)context of the first subroutine context up the Cx stack
int get_sub_context()
{
  I32 i;
  for (i = cxstack_ix; i >= 0; i--) {
    register const PERL_CONTEXT * const cx = cxstack+i;
    switch (CxTYPE(cx)) {
    default:
        continue;
    case CXt_SUB:
        return cx->blk_gimme;
    }
  }
  return G_VOID;
}


STATIC OP* unwind_return (pTHX_ OP *op, void *user_data) {
  dSP;
  SV* ctx;
  CV *unwind;

  PERL_UNUSED_VAR(op);
  PERL_UNUSED_VAR(user_data);

  ctx = get_sv("TryCatch::CTX", 0);
  if (ctx) {
    XPUSHs( ctx );
    PUTBACK;
  } else {
    PUSHMARK(SP);
    PUTBACK;

    call_pv("Scope::Upper::SUB", G_SCALAR);
    if (trycatch_debug & 1) {
      printf("No ctx, making it up\n");
    }

    SPAGAIN;
  }

  if (trycatch_debug & 1) {
    printf("unwinding to %d\n", (int)SvIV(*sp));

  }


  /* Can't use call_sv et al. since it resets PL_op. */
  /* call_pv("Scope::Upper::unwind", G_VOID); */

  unwind = get_cv("Scope::Upper::unwind", 0);
  XPUSHs( (SV*)unwind);
  PUTBACK;

  return CALL_FPTR(PL_ppaddr[OP_ENTERSUB])(aTHXR);
}


/* After the scope has been created, fix up the context */
STATIC OP* op_after_entertry(pTHX_ OP *op, void *user_data) {
  PERL_CONTEXT * cx = cxstack+cxstack_ix;

  // Sanity check the gimme, since we'll reset it in leavetry
  if (cx->blk_gimme != G_VOID) {
    Perl_croak(aTHX_ "Try Catch Internal Error: ENTERTRY op did not have VOID context (it was %d)", cx->blk_gimme);
  }
  cx->blk_gimme = get_sub_context();
  return op;
}

STATIC OP* op_before_leavetry(pTHX_ OP *op, void *user_data) {
  PERL_CONTEXT * cx = cxstack+cxstack_ix;
  cx->blk_gimme = G_VOID;
  return op;
}


/* Hook the OP_RETURN iff we are in hte same file as originally compiling. */
STATIC OP* check_return (pTHX_ OP *op, void *user_data) {

  const char* file = SvPV_nolen( (SV*)user_data );
  const char* cur_file = CopFILE(&PL_compiling);
  if (strcmp(file, cur_file))
    return op;
  if (trycatch_debug & 1) {
    printf("hooking OP_return at %s:%d\n", file, CopLINE(&PL_compiling));
  }

  hook_op_ppaddr(op, unwind_return, NULL);
  return op;
}



// If this eval scope should be marked by TryCatch, hook the ops
STATIC OP* check_leavetry (pTHX_ OP *op, void *user_data) {

  SV* eval_is_try = get_sv("TryCatch::NEXT_EVAL_IS_TRY", 0);

  if (SvOK(eval_is_try) && SvTRUE(eval_is_try)) {

    OP* entertry = ((LISTOP*)op)->op_first;

    if (trycatch_debug & 2) {
      const char* cur_file = CopFILE(&PL_compiling);
      int is_try = SvIVx(eval_is_try);
      printf("enterytry op 0x%x try=%d at %s:%d\n",
             op, is_try, cur_file, CopLINE(PL_curcop) );
    }

    SvIV_set(eval_is_try, 0);
    hook_op_ppaddr_around(entertry, NULL, op_after_entertry, NULL);
    hook_op_ppaddr_around(op, op_before_leavetry, NULL, NULL);
  }
  return op;
}

// eval {} starts off as an OP_ENTEREVAL, and then the PL_check[OP_ENTEREVAL]
// returns a newly created ENTERTRY (and LEAVETRY) ops without calling the
// PL_check for these new ops into OP_ENTERTRY. How ever versions prior to perl
// 5.10.1 didn't call the PL_check for these new opes
STATIC OP* check_entereval (pTHX_ OP *op, void *user_data) {
  if (op->op_type == OP_LEAVETRY) {
    return check_leavetry(aTHX_ op, user_data);
  }
  return op;
}


void dualvar_id(SV* sv, UV id) {

  char* file = CopFILE(&PL_compiling);
  STRLEN len = strlen(file);

  (void)SvUPGRADE(sv,SVt_PVNV);

  sv_setpvn(sv,file,len);
#ifdef SVf_IVisUV
  SvUV_set(sv, id);
  SvIOK_on(sv);
  SvIsUV_on(sv);
#else
  SvIV_set(sv, id);
  SvIOK_on(sv);
#endif
}

SV* install_op_check(int op_code, hook_op_ppaddr_cb_t hook_fn) {
  SV* ret;
  UV id;

  ret = newSV(0);

  id = hook_op_check( op_code, hook_fn, ret );
  dualvar_id(ret, id);

  return ret;
}

MODULE = TryCatch PACKAGE = TryCatch::XS

PROTOTYPES: DISABLE

void
install_return_op_check()
  CODE:
    ST(0) = install_op_check(OP_RETURN, check_return);
    XSRETURN(1);

void
install_try_op_check()
  CODE:
    // TODO: Deal with perl 5.10.1+
    ST(0) = install_op_check(OP_ENTEREVAL, check_entereval);
    XSRETURN(1);

void
uninstall_return_op_check(id)
SV* id
  CODE:
#ifdef SVf_IVisUV
    UV uiv = SvUV(id);
#else
    UV uiv = SvIV(id);
#endif
    hook_op_check_remove(OP_RETURN, uiv);
  OUTPUT:

void dump_stack()
  CODE:
    dump_cxstack();
  OUTPUT:

BOOT:
{
  char *debug = getenv ("TRYCATCH_DEBUG");
  int lvl = 0;
  if (debug && (lvl = atoi(debug)) && (lvl & (~1)) ) {
    trycatch_debug = lvl >> 1;
    printf("TryCatch XS debug enabled: %d\n", trycatch_debug);
  }
}
