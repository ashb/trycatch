#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#define NEED_PL_parser_GLOBAL
#define NEED_newRV_noinc_GLOBAL
#define NEED_sv_2pv_flags_GLOBAL
#include "ppport.h"

#include "hook_op_check.h"
#include "hook_op_ppaddr.h"

#ifndef CvISXSUB
# define CvISXSUB(cv) CvXSUB(cv)
#endif

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
        printf("***\n* eval stack %d: WA: %d\n", (int)i, cx->blk_gimme);
        /* sv_dump((SV*)cx->blk_eval.cv); */
        break;
    case CXt_SUB:
        printf("***\n* cx stack %d: WA: %d\n", (int)i, cx->blk_gimme);
        sv_dump((SV*)cx->blk_sub.cv);
        break;
    }
  }
  return i;
}

/* Return the (array)context of the first subroutine context up the Cx stack */
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


/* the implementation of 'return' op inside try blocks. */
STATIC OP*
try_return (pTHX_ OP *op, void *user_data) {
  dSP;
  SV* ctx;
  CV *unwind;

  PERL_UNUSED_VAR(op);
  PERL_UNUSED_VAR(user_data);

  ctx = get_sv("TryCatch::CTX", 0);
  if (ctx) {
    XPUSHs( ctx );
    PUTBACK;
    if (trycatch_debug & 2) {
      printf("have a $CTX of %d\n", SvIV(ctx));
    }
  } else {
    PUSHMARK(SP);
    PUTBACK;

    call_pv("Scope::Upper::SUB", G_SCALAR);
    if (trycatch_debug & 2) {
      printf("No ctx, making it up\n");
    }

    SPAGAIN;
  }

  if (trycatch_debug & 2) {
    printf("unwinding to %d\n", (int)SvIV(*sp));

  }


  /* Can't use call_sv et al. since it resets PL_op. */
  /* call_pv("Scope::Upper::unwind", G_VOID); */

  unwind = get_cv("Scope::Upper::unwind", 0);
  XPUSHs( (SV*)unwind);
  PUTBACK;

  /* pp_entersub gets the XSUB arguments from @_ if there are any.
   * Bypass this as we pushed the arguments directly on the stack. */

  if (CvISXSUB(unwind))
    AvFILLp(GvAV(PL_defgv)) = -1;

  return CALL_FPTR(PL_ppaddr[OP_ENTERSUB])(aTHX);
}

/* The implementation of wantarray op/keyword inside try blocks. */
STATIC OP*
try_wantarray( pTHX_ OP *op, void *user_data ) {
  dVAR;
  dSP;
  EXTEND(SP, 1);

  PERL_UNUSED_VAR(op);
  PERL_UNUSED_VAR(user_data);

  /* We want the context from the closest subroutine, not from the closest
   * block
   */
  switch ( get_sub_context() ) {
  case G_ARRAY:
    RETPUSHYES;
  case G_SCALAR:
    RETPUSHNO;
  default:
    RETPUSHUNDEF;
  }
}


/* After the scope has been created, fix up the context of the C<eval {}> block */
STATIC OP*
try_after_entertry(pTHX_ OP *op, void *user_data) {
  PERL_CONTEXT * cx = cxstack+cxstack_ix;
  cx->blk_gimme = get_sub_context();
  return op;
}



STATIC OP*
hook_if_correct_file( pTHX_ OP *op, void* user_data ) {
  SV* eval_is_try;

  const char* wanted_file = SvPV_nolen( (SV*)user_data );
  const char* cur_file = CopFILE( &PL_compiling );
  if ( strcmp(wanted_file, cur_file) ) {
    if ( trycatch_debug & 4 )
      Perl_warn( aTHX_ "Not hooking OP %s since its not in '%s'", PL_op_name[op->op_type], wanted_file );
    return op;
  }
  if (trycatch_debug & 4) {
    Perl_warn(aTHX_ "hooking OP %s", PL_op_name[op->op_type]);
  }

  switch (op->op_type) {
    case OP_WANTARRAY:
      hook_op_ppaddr(op, try_wantarray, NULL);
      break;

    case OP_RETURN:
      hook_op_ppaddr(op, try_return, NULL);
      break;

#if (PERL_BCDVERSION < 0x5011000)
    case OP_ENTEREVAL:
      /* Do nothing if its still an entereval */
      break;
#endif

    case OP_LEAVETRY:
      /* eval {} starts off as an OP_ENTEREVAL, and then the PL_check[OP_ENTEREVAL]
         returns a newly created ENTERTRY (and LEAVETRY) ops without calling the
         PL_check for these new ops into OP_ENTERTRY. How ever versions prior to perl
         5.10.1 didn't call the PL_check for these new ops */
      hook_if_correct_file( aTHX_ ((LISTOP*)op)->op_first, user_data );
      break;

    case OP_ENTERTRY:
      eval_is_try = get_sv("TryCatch::NEXT_EVAL_IS_TRY", 0);
      if ( eval_is_try && SvOK( eval_is_try ) && SvTRUE( eval_is_try ) ) {
        /* We've hooked a try block, so reset the flag */
        SvIV_set( eval_is_try, 0 );
        hook_op_ppaddr_around( op, NULL, try_after_entertry, NULL );
      }
      break;

    default:
      fprintf(stderr, "Try Catch Internal Error: Unknown op %d: %s\n", op->op_type, PL_op_name[op->op_type]);
      abort();
  }
  return op;
}


/* Hook all the *_check functions we need. Return an arrayref of:
 *
 * [ current_file_name, op_id, hook_id, op_id, hook_id, ... ]
 */
SV*
xs_install_op_checks() {
  SV *sv_curfile = newSV( 0 );
  AV* av = newAV();

  /* Get the filename we install check op hooks into. Need this so that we
     don't hook ops if a require Other::Module happens in a try block. */
  char* file = CopFILE(&PL_compiling);
  STRLEN len = strlen(file);

  (void)SvUPGRADE(sv_curfile,SVt_PVNV);

  sv_setpvn(sv_curfile,file,len);
  av_push(av, sv_curfile);

  #define do_hook(op) \
    av_push(av, newSVuv( (op) ) ); \
    av_push(av, newSVuv( hook_op_check( op, hook_if_correct_file, sv_curfile ) ) ); \

  /* This replace return with an unwird */
  do_hook( OP_RETURN );
  /* This fixes 'wantarray' keyword */
  do_hook( OP_WANTARRAY );
  /* And this gives the right context to C<return foo()> in a try block */
  do_hook( OP_ENTERTRY );

#if (PERL_BCDVERSION < 0x5011000)
  /* Prior to 5.10.1(?) the ENTERTRY starts out as an ENTEREVAL and doesn't get
   * PL_checked, so we need to hook ENTEREVAL (string eval) too and see if the
   * type got changed. */
  do_hook( OP_ENTEREVAL );
#endif

  #undef do_hook

  /* Get an array ref form the array, return that. This keeps the sv_curfile alive */
  return newRV_noinc( (SV*) av );
}


MODULE = TryCatch PACKAGE = TryCatch::XS

PROTOTYPES: DISABLE

void
install_op_checks()
  CODE:
    ST(0) = xs_install_op_checks();
    XSRETURN(1);

void
uninstall_op_checks( aref )
SV* aref;
  PREINIT:
    AV* av;
    SV *op, *id;
  CODE:
    if ( !SvROK(aref) && SvTYPE(SvRV(aref)) != SVt_PVAV ) {
      Perl_croak(aTHX_ "ArrayRef expected");
    }
    av = (AV*)(SvRV(aref));
    /* throw away cur_file */
    av_shift(av);
    while (av_len(av) != -1) {
      op = av_shift(av);
      id = av_shift(av);
      hook_op_check_remove( SvUV(op), SvUV(id) );
    }
  OUTPUT:

void dump_stack()
  CODE:
    dump_cxstack();
  OUTPUT:

void set_linestr_offset(int offset)
  CODE:
    char* linestr = SvPVX(PL_linestr);
    PL_bufptr = linestr + offset;

BOOT:
{
  char *debug = getenv ("TRYCATCH_DEBUG");
  /* Debug meanings:
      1 - line string changes (from the .pm)
      2 - Debug unwid contexts
      4 - debug op hooking
   */
  if (debug && (trycatch_debug = atoi(debug)) ) {
    fprintf(stderr, "TryCatch XS debug enabled: %d\n", trycatch_debug);
  }
}
