#import "@preview/curryst:0.6.0": rule, prooftree, rule-set

#metadata((
  title: "simply typed λ-calculus",
  description: "hilbert-style formal system for the simply typed lambda calculus",
  keywords: ("plt", "logic"),
  published: "2026-11-03",
  updated: none,
)) <meta>
#show math.equation.where(block: true): it => html.elem("div", attrs: (class: "equation"), it)

#title[simply typed $lambda$-calculus]

= alphabet
$
  cal(L) = { lambda quad . quad "(" quad ")" quad v quad K quad prime quad : quad -> quad "type" quad tack.r quad "," quad epsilon quad diamond.stroked.small }
$

= formation rules
== grammar
#let alt = $class("relation", bar.v)$
$
  x &::= v alt x prime \
  M, N &::= x alt (lambda x : A . M) alt (M thick N) \
  X &::= K alt X prime \
  A, B &::= X alt (A -> B) \
  Gamma, Delta &::= epsilon alt Gamma, x : A \
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

base types:
- $K$ is a base type
- if $X$ is a base type, then $X prime$ is a base type

types:
- every base type is a type
- if $A$ is a type and $B$ is a type, then $(A -> B)$ is a type

contexts:
- $epsilon$ is a context
- if $Gamma$ is a context, $x$ is a variable, and $A$ is a type, then $Gamma, x : A$ is a context

wffs:
- if $Gamma$ is a context, then $Gamma tack.r diamond.stroked.small$ is a wff ($Gamma$ is legal)
- if $Gamma$ is a context and $A$ is a type, then $Gamma tack.r A "type"$ is a wff ($A$ is legal in $Gamma$)
- if $Gamma$ is a context, $M$ is a term, and $A$ is a type, then $Gamma tack.r M : A$ is a wff ($M$ has type $A$ in $Gamma$)

== domain
$
  "dom"(epsilon) &= {} \
  "dom"((Gamma, x : A)) &= "dom"(Gamma) union {x}
$

== context concat
$
  Gamma, epsilon &= Gamma \
  Gamma, (Delta, x : A) &= (Gamma, Delta), x : A
$

= rules of inference
== environments
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin x quad x in.not "dom"(Gamma)$,
    $Gamma tack.r A "type"$,
    $Gamma, x : A tack.r diamond.stroked.small$,
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
    name: [Val Fun],
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

== types
#html.frame(rule-set(
  prooftree(rule(
    name: [Type Const],
    $Gamma tack.r diamond.stroked.small$,
    $Gamma tack.r X "type"$,
  )),
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

