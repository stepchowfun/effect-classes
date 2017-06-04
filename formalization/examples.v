Require Import syntax.
Require Import typingRules.

Definition ex1 := eunit.

Theorem ex1WellTyped : Ø ⊢ ex1 ∈ tunit.
Proof. apply aunit. Qed.

Definition ex2 := λ @ "x" ∈ tunit ⇒ evar (@ "x").

Theorem ex2WellTyped : Ø ⊢ ex2 ∈ tunit → tunit.
Proof. apply aabs. apply avar. reflexivity. Qed.
