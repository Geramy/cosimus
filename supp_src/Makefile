include ../Makefile.inc
LIBS=-lssl -lm
SRCS= lib_dbuf.c lib_debug.c lib_hash.c lib_hash_func.c lib_lists.c lib_os.c lib_poll.c lib_sock.c lib_httpd.c lib_timers.c lib_uuid.c uuid_sysdep.c lua_libsu.c 
INCLUDES= lib_dbuf.h lib_debug.h lib_hash.h lib_hash_func.h lib_lists.h lib_os.h lib_poll.h lib_sock.h lib_sock_intern.h lib_httpd.h lib_timers.h lib_uuid.h uuid_sysdep.h libsupp.h
OBJS= $(subst .c,.o,$(SRCS))

DEPEND=makedepend

all: supplib

supplib: depend libsupp.a

libsupp.a: $(OBJS)
	 $(AR) $@ $?
	 $(RANLIB) $@

libreload.a: lua_libreload.o
	 $(CC) -o $@ $^ $(LIBS)
	

clean:
	$(RM) *.o libsupp.a Makefile.depend

depend: Makefile.depend
	
Makefile.depend: $(SRCS) $(INCLUDES)
	$(DEPEND) $(CFLAGS) $(INCLUDES) $(SRCS) -f - >Makefile.depend


include Makefile.depend

