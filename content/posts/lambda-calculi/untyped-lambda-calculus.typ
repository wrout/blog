#import "@preview/curryst:0.6.0": rule, prooftree, rule-set

#set document(
  title: [untyped $lambda$-calculus],
  description: "hilbert-style formal system for the untyped lambda calculus",
  keywords: ("plt", "logic"),
)
#metadata((published: "2026-10-30", updated: none)) <post>

= alphabet
$
  cal(L) = { lambda quad . quad "(" quad ")" quad v quad prime quad tack.r quad "," quad epsilon quad diamond.stroked.small }
$

= formation rules
== grammar
#let alt = $class("relation", bar.v)$
$
  x &::= v alt x prime \
  M, N &::= x alt (lambda x . M) alt (M thick N) \
  Gamma, Delta &::= epsilon alt Gamma, x \
  phi &::= Gamma tack.r diamond.stroked.small alt Gamma tack.r M
$

== in words
variables:
- $v$ is a variable
- if $x$ is a variable, then $x prime$ is a variable

terms:
- every variable is a term
- if $x$ is a variable and $M$ is a term, then $(lambda x . M)$ is a term
- if $M$ and $N$ are terms, then $(M thick N)$ is a term

contexts:
- $epsilon$ is a context
- if $Gamma$ is a context and $x$ is a variable, then $Gamma, x$ is a context

wffs:
- if $Gamma$ is a context, then $Gamma tack.r diamond.stroked.small$ is a wff ($Gamma$ is well-formed)
- if $Gamma$ is a context and $M$ is a term, then $Gamma tack.r M$ is a wff ($M$ is well-scoped in $Gamma$)

== domain
$
  "dom"(epsilon) &= {} \
  "dom"((Gamma, x)) &= "dom"(Gamma) union {x}
$

== context concat
$
  Gamma, epsilon &= Gamma \
  Gamma, (Delta, x) &= (Gamma, Delta), x
$

= rules of inference
== environments
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin x quad x in.not "dom"(Gamma)$,
    $Gamma tack.r diamond.stroked.small$,
    $Gamma, x tack.r diamond.stroked.small$,
  )),
))

== terms
#html.frame(rule-set(
  prooftree(rule(
    name: [Val $x$],
    $Gamma, x, Delta tack.r diamond.stroked.small$,
    $Gamma, x, Delta tack.r x$,
  )),
  prooftree(rule(
    name: [Val Fun],
    $Gamma, x tack.r M$,
    $Gamma tack.r (lambda x . M)$,
  )),
))
#html.frame(rule-set(
  prooftree(rule(
    name: [Val Appl],
    $Gamma tack.r M$,
    $Gamma tack.r N$,
    $Gamma tack.r (M thick N)$,
  )),
))

= axioms
#html.frame(rule-set(
  prooftree(rule(
    name: $"Env" thin epsilon$,
    $epsilon tack.r diamond.stroked.small$,
  )),
))

