:- module det_errors.

:- interface.

:- pred p1(int::in) is det.
:- pred p2(int::in) is det.
:- pred p3(int::in) is det.
:- pred p4(int::in) is det.
:- pred p5(int::in) is det.

:- type t ---> a ; b ; c ; d ; e ; f ; g.

:- pred q(t::in, int::out) is det.

:- implementation.
:- import_module int.

p1(42).
p2(X) :- X = 42.
p3(X) :- X = 42.
p4(X) :- X = 21 + 21.
p5(_) :- true.

q(a, 1).
q(b, 2).
q(c, 3).
