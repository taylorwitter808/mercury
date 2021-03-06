%-----------------------------------------------------------------------------%
% vim: ft=mercury ts=4 sw=4 et
%-----------------------------------------------------------------------------%
% Copyright (C) 2001 The University of Melbourne.
% This file may only be copied under the terms of the GNU Library General
% Public License - see the file COPYING.LIB in the Mercury distribution.
%-----------------------------------------------------------------------------%
%
% Module: posix.closedir.m.
% Main author: Michael Day <miked@lendtech.com.au>
%
%-----------------------------------------------------------------------------%

:- module posix.closedir.
:- interface.

:- import_module io.

:- pred closedir(dir::in, io::di, io::uo) is det.

%-----------------------------------------------------------------------------%
%-----------------------------------------------------------------------------%

:- implementation.

:- pragma foreign_decl("C", "
#include <sys/types.h>
#include <dirent.h>
").

:- pragma foreign_proc("C",
    closedir(Dir::in, IO0::di, IO::uo),
    [promise_pure, will_not_call_mercury, thread_safe, tabled_for_io],
"
    closedir(Dir);
    IO = IO0;
").

%-----------------------------------------------------------------------------%
:- end_module posix.closedir.
%-----------------------------------------------------------------------------%
