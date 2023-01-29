#include <string.h>
#include "chezscheme.h"
#include "racketcs.h"
  
int main(int argc, char *argv[])
{
  racket_boot_arguments_t ba;
  
  memset(&ba, 0, sizeof(ba));

  if ((argc > 1) && !strcmp(argv[1], "run"))
    racket_boot(&ba);
  
  return 0;
}
