#include "scheme.h"

static int run(Scheme_Env *e, int argc, char *argv[]) {
  return 0;
}

int main(int argc, char *argv[]) {
  return scheme_main_setup(1, run, argc, argv);
}
