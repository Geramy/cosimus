
/**************************************************************************
*
*  Copyright © 2008-2009 Andrew Yourtchenko, ayourtch@gmail.com.
*
*  Permission is hereby granted, free of charge, to any person obtaining 
* a copy of this software and associated documentation files (the "Software"), 
* to deal in the Software without restriction, including without limitation 
* the rights to use, copy, modify, merge, publish, distribute, sublicense, 
* and/or sell copies of the Software, and to permit persons to whom 
* the Software is furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included 
* in all copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
* OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR 
* OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, 
* ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
* OR OTHER DEALINGS IN THE SOFTWARE. 
*
*****************************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luazip.h"

#include "lib_debug.h"
#include "lib_uuid.h"
#include "lib_httpd.h"
#include "lib_os.h"
#include "fmv.h"
#include "pktsmv.h"
#include "libsupp.h"

LUALIB_API int luaopen_base64(lua_State *L);


lua_State *L;
int dump_and_leave = 0;

void
sigterm_handler(int x)
{
  debug(DBG_GLOBAL, 0, "SIG! param: %d", x);
  dump_and_leave = 1;
}


int main(int argc, char *argv[]) 
{
  //set_debug_level(DBG_GLOBAL, 100);
  set_signal_handler(SIGINT, sigterm_handler);
  
  L = lua_open();
  luaL_openlibs(L);
  luaopen_zip(L);
  luaopen_base64(L);
  luaopen_libfmv(L);
  luaopen_libpktsmv(L);
  luaopen_libsupp(L);
  if (luaL_dofile(L,argv[1])!=0) {
    fprintf(stderr,"%s\n",lua_tostring(L,-1));
  } else {
    while (!dump_and_leave) {
      sock_one_cycle(1000, L);
    }
    lua_getglobal(L, "interrupt_save_state");
    lua_pcall_with_debug(L, 0, 0, 0, 0);
  }
  lua_close(L);
  exit(1);
  return 0;
}
