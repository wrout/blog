#import "@preview/curryst:0.6.0": rule, prooftree, rule-set

#metadata((
  title: "polymorphic λ-calculus",
  description: "hilbert-style formal system for the polymorphic lambda calculus",
  keywords: ("plt", "logic"),
  published: "2026-11-06",
  updated: none,
)) <meta>
#show math.equation.where(block: true): it => html.elem("div", attrs: (class: "equation"), it)

#title[polymorphic $lambda$-calculus]

= alphabet
$
  cal(L) = { Lambda quad lambda quad . quad "(" quad ")" quad "[" quad "]" quad v quad V quad prime quad : quad -> quad "type" quad forall quad tack.r quad "," quad epsilon quad diamond.stroked.small }
$

= formation rules
== grammar
#let alt = $class("relation", bar.v)$
$
  x &::= v alt x prime \
  M, N &::= x alt (lambda x : A . M) alt (M thick N) alt (Lambda X . M) alt (M thick [A]) \
  X, Y &::= V alt X prime \
  A, B &::= X alt (forall X . A) alt (A -> B) \
  Gamma, Delta &::= epsilon alt Gamma, X "type" alt Gamma, x : A \
  phi &::= Gamma tack.r diamond.stroked.small alt Gamma tack.r A "type" alt Gamma tack.r M : A
$

== in words
variables:
- $v$ is a variable
- if $x$ is a variable, then $x prime$ is a variable

terms:
- every variable is a term
- if $x$ is a variable, $A$ is a type, and $M$ is a term, then $(lambda x : A . M)$ is a term
- if $M$ and $N$ are terms, then $(M thick N)$ is a term
- if $X$ is a type variable and $M$ is a term, then $(Lambda X . M)$ is a term
- if $M$ is a term and $A$ is a type, then $(M thick [A])$ is a term

type variables:
- $V$ is a type variable
- if $X$ is a type variable, then $X prime$ is a type variable

types:
- every type variable is a type
- if $X$ is a type variable and $A$ is a type, then $(forall X . A)$ is a type
- if $A$ is a type and $B$ is a type, then $(A -> B)$ is a type

contexts:
- $epsilon$ is a context
- if $Gamma$ is a context and $X$ is a type variable, then $Gamma, X "type"$ is a context
- if $Gamma$ is a context, $x$ is a variable, and $A$ is a type, then $Gamma, x : A$ is a context

wffs:
- if $Gamma$ is a context, then $Gamma tack.r diamond.stroked.small$ is a wff ($Gamma$ is legal)
- if $Gamma$ is a context and $A$ is a type, then $Gamma tack.r A "type"$ is a wff ($A$ is legal in $Gamma$)
- if $Gamma$ is a context, $M$ is a term, and $A$ is a type, then $Gamma tack.r M : A$ is a wff ($M$ has type $A$ in $Gamma$)

== domain
$
  "dom"_("terms")(epsilon) &= {} \
  "dom"_("terms")((Gamma, X "type")) &= "dom"_("terms")(Gamma) \ 
  "dom"_("terms")((Gamma, x : A)) &= "dom"_("terms")(Gamma) union {x}
$

$
  "dom"_("types")(epsilon) &= {} \
  "dom"_("types")((Gamma, X "type")) &= "dom"_("types")(Gamma) union {X} \ 
  "dom"_("types")((Gamma, x : A)) &= "dom"_("types")(Gamma)
$

== context concat
$
  Gamma, epsilon &= Gamma \
  Gamma, (Delta, X "type") &= (Gamma, Delta), X "type" \
  Gamma, (Delta, x : A) &= (Gamma, Delta), x : A
$

== free type variables
$
  "FTV"(X) &= {X} \
  "FTV"((forall X . A)) &= "FTV"(A) without {X} \
  "FTV"((A -> B)) &= "FTV"(A) union "FTV"(B)
$

== substitution
#let subst(b, x) = $[#b \/ #x]$
$
  subst(B, X) X &= B \
  subst(B, X) Y &= Y quad Y != X \
  subst(B, X) (forall X . A) &= (forall X . A) \
  subst(B, X) (forall Y . A) &= (forall Y . subst(B, X) A) quad Y != X, Y in.not "FTV"(B) \
  subst(B, X) (forall Y . A) &= "undefined" quad Y != X, Y in "FTV"(B) \
  subst(B, X) (A_1 -> A_2) &= (subst(B, X) A_1 -> subst(B, X) A_2)
$

= rules of inference
== environments
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin x quad x in.not "dom"_("terms")(Gamma)$,
    $Gamma tack.r A "type"$,
    $Gamma, x : A tack.r diamond.stroked.small$,
  )),
))
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin X quad X in.not "dom"_("types")(Gamma)$,
    $Gamma tack.r diamond.stroked.small$,
    $Gamma, X "type" tack.r diamond.stroked.small$,
  )),
))

== terms
#html.frame(rule-set(
  prooftree(rule(
    name: [Val $x$],
    $Gamma, x : A, Delta tack.r diamond.stroked.small$,
    $Gamma, x : A, Delta tack.r x : A$,
  )),
  prooftree(rule(
    name: [Val Abs],
    $Gamma, x : A tack.r M : B$,
    $Gamma tack.r (lambda x : A . M) : (A -> B)$,
  )),
))
#html.frame(rule-set(
  prooftree(rule(
    name: [Val Appl],
    $Gamma tack.r M : (A -> B)$,
    $Gamma tack.r N : A$,
    $Gamma tack.r (M thick N) : B$,
  )),
))
#html.frame(rule-set(
  prooftree(rule(
    name: [Val Abs2],
    $Gamma, X "type" tack.r M : A$,
    $Gamma tack.r (Lambda X . M) : (forall X . A)$,
  )),
  prooftree(rule(
    name: [Val Appl2],
    $Gamma tack.r M : (forall X . A)$,
    $Gamma tack.r B "type"$,
    $Gamma tack.r (M thick [B]) : subst(B, X) A$,
  )),
))

== types
#html.frame(rule-set(
  prooftree(rule(
    name: [Type $X$],
    $Gamma, X "type", Delta tack.r diamond.stroked.small$,
    $Gamma, X "type", Delta tack.r X "type"$,
  )),
  prooftree(rule(
    name: [Type Forall],
    $Gamma, X "type" tack.r A "type"$,
    $Gamma tack.r (forall X . A) "type"$,
  )),
))
#html.frame(rule-set(
  prooftree(rule(
    name: [Type Arrow],
    $Gamma tack.r A "type"$,
    $Gamma tack.r B "type"$,
    $Gamma tack.r (A -> B) "type"$,
  )),
))

= axioms
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin epsilon$,
    $epsilon tack.r diamond.stroked.small$,
  )),
))

