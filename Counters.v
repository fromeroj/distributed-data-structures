(**
   State-based counters, as described in:

   A Comprehensive Study of Convergent and Commutative Replicated Data Types
   by Shapiro, Preguiça, Baquero, Zawirski.
   http://hal.upmc.fr/docs/00/55/55/88/PDF/techreport.pdf
**)

Require Import Coq.FSets.FMaps.
Require Import Coq.FSets.FSets.
Require Import Coq.Arith.Arith.
Require Import Coq.Structures.OrdersEx.
Require Import Coq.MSets.MSetList.

(* Taken from LambdaJS to provide backwards compatibility b/t Ordered/OrderedType *)
Module UOT_to_OrderedTypeLegacy (UOT:OrderedType) <:
  (IsEqOrig UOT) <: OrderedType.OrderedType.

  Definition t := UOT.t.
  Definition lt := UOT.lt.
  Definition eq := UOT.eq.
  Definition eq_refl := let (r, _, _) := UOT.eq_equiv in r.
  Definition eq_sym := let (_, s, _) := UOT.eq_equiv in s.
  Definition eq_trans := let (_, _, t) := UOT.eq_equiv in t.

  Lemma lt_trans : forall x y z : t, UOT.lt x y -> UOT.lt y z -> UOT.lt x z.
  Proof. destruct UOT.lt_strorder as [i t]. apply t. Qed.

  Lemma lt_not_eq : forall x y : t, UOT.lt x y -> ~ UOT.eq x y.
  Proof. destruct UOT.lt_strorder as [i t]. intros. intro. rewrite H0 in *.
         exact (i y H). Qed.

  Definition compare (x y : t) : OrderedType.Compare UOT.lt UOT.eq x y :=
    match (CompareSpec2Type (UOT.compare_spec x y)) with
      | CompLtT l => OrderedType.LT l
      | CompEqT e => OrderedType.EQ e
      | CompGtT g => OrderedType.GT g
    end.

  Definition eq_dec := UOT.eq_dec.
  Definition eq_equiv := UOT.eq_equiv.
  Definition lt_strorder := UOT.lt_strorder.
  Definition lt_compat := UOT.lt_compat.
End UOT_to_OrderedTypeLegacy.

Lemma leb_max_mono : forall n m,
  leb n (max n m) = true.
Proof.
  intros.
  generalize dependent m.
  induction n; induction m; auto with arith; simpl.
  rewrite leb_correct; auto. rewrite IHn; reflexivity.
Qed.

Module Nat_as_Legacy_OT := UOT_to_OrderedTypeLegacy (Nat_as_OT).

(* Map of clocks, which are nat -> nat. *)

Module ClockMap := FMapWeakList.Make (Nat_as_Legacy_OT).
Module ClockMapFacts := FMapFacts.Facts (ClockMap).

(* Merge two clocks. *)
Definition Clock_merge (n1 n2 : option nat) :=
  match n1, n2 with
    | None, None => None
    | Some n, None => Some n
    | None, Some n => Some n
    | Some n1', Some n2' => Some (max n1' n2')
  end.

(* Compare two clocks. *)
Definition Clock_compare (n1 n2 : option nat) :=
  match n1, n2 with
    | None, None => None
    | Some n, None => Some false
    | None, Some n => Some true
    | Some n1', Some n2' => Some (leb n1' n2')
  end.

Definition Clock_true (n1 n2 : option nat) :=
  match n1, n2 with
    | None, None => None
    | Some n, None => Some true
    | None, Some n => Some true
    | Some n1', Some n2' => Some true
  end.

(* Proofs of the clock merging being a valid LUB. *)

Lemma Clock_merge_comm : forall n1 n2, 
  Clock_merge n1 n2 = Clock_merge n2 n1.
Proof.
  intros. destruct n1; destruct n2; auto.
  simpl. f_equal. apply Max.max_comm.
Qed.

Lemma Clock_merge_idempotent : forall n1, 
  Clock_merge n1 n1 = n1.
Proof.
  intros. destruct n1; auto; simpl.
  f_equal. apply Max.max_idempotent.
Qed.

Lemma Clock_merge_assoc : forall n1 n2 n3, 
  Clock_merge n1 (Clock_merge n2 n3) = Clock_merge (Clock_merge n1 n2) n3.
Proof.
  intros. destruct n1; destruct n2; destruct n3; auto.
  unfold Clock_merge. f_equal. apply Max.max_assoc.
Qed.

Lemma Clock_compare_refl : forall x,
  Clock_compare x x = Clock_true x x.
Proof.
  intros; destruct x; auto. unfold Clock_compare. unfold Clock_true.
  destruct n; auto. f_equal. simpl. rewrite leb_correct; auto.
Qed.

(* Grow only counter, representing a vector of clocks which are nats. *)

(* Initialize an empty G_Counter. *)
Definition G_Counter := ClockMap.t nat.
Definition G_Counter_init : G_Counter := ClockMap.empty nat.

(* Increment a G_Counter for a particular actor. *)
Definition G_Counter_incr actor clocks :=
  match ClockMap.find actor clocks with
    | None => ClockMap.add actor 1 clocks
    | Some count => (ClockMap.add actor (S count) clocks)
  end.

(* Reveal the current value of a G_Counter. *)
Definition G_Counter_reveal clocks :=
  ClockMap.fold (fun key elt acc => (plus acc elt)) clocks 0.

(* Merge two G_Counters. *)
Definition G_Counter_merge c1 c2 :=
  ClockMap.map2 Clock_merge c1 c2.

(* Verify that two G_Counters are equal. *)
Definition G_Counter_equal (c1 c2 : G_Counter) :=
  ClockMap.Equal c1 c2.

(* Compare two counters. *)
Definition G_Counter_compare (c1 c2 : G_Counter) :=
  ClockMap.Equal
    (ClockMap.map2 Clock_compare c1 c2) (ClockMap.map2 Clock_true c1 c2).

(* Proofs regarding G_Counter operations. *)
Theorem G_Counter_merge_comm : forall c1 c2,
  G_Counter_equal (G_Counter_merge c1 c2) (G_Counter_merge c2 c1).
Proof.
  intros; unfold G_Counter_merge.
  unfold ClockMap.Equal; intro.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  apply Clock_merge_comm.
Qed.

Theorem G_Counter_merge_idempotent : forall clocks,
  G_Counter_equal (G_Counter_merge clocks clocks) clocks.
Proof.
  intros; unfold G_Counter_merge.
  unfold ClockMap.Equal; intro.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  apply Clock_merge_idempotent.
Qed.

Theorem G_Counter_merge_assoc : forall c1 c2 c3,
  G_Counter_equal
    (G_Counter_merge c1 (G_Counter_merge c2 c3))
    (G_Counter_merge (G_Counter_merge c1 c2) c3).
Proof.
  intros; unfold G_Counter_merge.
  unfold ClockMap.Equal; intro.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  repeat rewrite <- Clock_merge_assoc; reflexivity.
Qed.

Theorem G_Counter_compare_idempotent : forall clocks,
  G_Counter_compare clocks clocks.
Proof.
  intros; unfold G_Counter_compare; unfold ClockMap.Equal; intro.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  apply Clock_compare_refl.
Qed.

Theorem G_Counter_incr_mono : forall clocks actor,
  G_Counter_compare clocks (G_Counter_incr actor clocks).
Proof.
  intros; unfold G_Counter_compare; unfold ClockMap.Equal; intro.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  elim (eq_nat_dec actor y); intro. 
    subst. unfold Clock_compare, Clock_true. unfold G_Counter_incr. simpl.
    destruct (ClockMap.find y clocks).
      rewrite ClockMapFacts.add_eq_o. f_equal. 
        induction n; auto. reflexivity. reflexivity.
      unfold G_Counter_incr.
      destruct (ClockMap.find actor clocks) eqn:factor.
        rewrite ClockMapFacts.add_neq_o; auto. apply Clock_compare_refl. 
        rewrite ClockMapFacts.add_neq_o; auto. apply Clock_compare_refl. 
Qed.

Theorem G_Counter_merge_mono : forall c1 c2,
  G_Counter_compare c1 (G_Counter_merge c1 c2).
Proof.
  intros; unfold G_Counter_compare.
  unfold ClockMap.Equal; intro.
  unfold Clock_compare, Clock_true, G_Counter_merge.
  repeat rewrite ClockMapFacts.map2_1bis; auto.
  destruct (ClockMap.find y c1); 
    destruct (ClockMap.find y c2); simpl; f_equal.
      apply leb_max_mono.
      rewrite leb_correct; auto.
Qed.

(* Positive/negative counter, two vector clocks. *)

(* Initialize an empty PN_Counter. *)
Definition PN_Counter := (G_Counter * G_Counter)%type.
Definition PN_Counter_init : PN_Counter := (G_Counter_init, G_Counter_init).

(* Increment a PN_Counter for a particular actor. *)
Definition PN_Counter_incr actor (clocks : PN_Counter) :=
  pair (G_Counter_incr actor (fst clocks)) (snd clocks).

(* Decrement a PN_Counter for a particular actor. *)
Definition PN_Counter_decr actor (clocks : PN_Counter) :=
  pair (fst clocks) (G_Counter_incr actor (snd clocks)).

(* Reveal the current value of a PN_Counter. *)
Definition PN_Counter_reveal clocks :=
  minus (G_Counter_reveal (fst clocks)) (G_Counter_reveal (snd clocks)).

(* Merge two PN_Counters. *)
Definition PN_Counter_merge c1 c2 :=
  pair (G_Counter_merge (fst c1) (fst c2)) (G_Counter_merge (snd c1) (snd c2)).

(* Compare two G_Counters. *)
Definition PN_Counter_compare (c1 c2 : PN_Counter) :=
  and (G_Counter_compare (fst c1) (fst c2)) (G_Counter_compare (snd c1) (snd c2)).

(* Verify that two PN_Counters are equal. *)
Definition PN_Counter_equal (c1 c2 : PN_Counter) :=
  ClockMap.Equal (fst c1) (fst c2) /\ ClockMap.Equal (snd c1) (snd c2).

(* Proofs regarding PN_Counter operations. *)
Theorem PN_Counter_merge_comm : forall c1 c2,
  PN_Counter_equal (PN_Counter_merge c1 c2) (PN_Counter_merge c2 c1).
Proof.
  intros.
  unfold PN_Counter_equal.
  split; unfold ClockMap.Equal; intros;
    unfold PN_Counter_merge; unfold G_Counter_merge; simpl;
    repeat rewrite ClockMapFacts.map2_1bis; auto.
    apply Clock_merge_comm.
    apply Clock_merge_comm.
Qed.

Theorem PN_Counter_merge_idempotent : forall c1,
  PN_Counter_equal (PN_Counter_merge c1 c1) c1.
Proof.
  intros.
  unfold PN_Counter_equal.
  split; unfold ClockMap.Equal; intros;
    unfold PN_Counter_merge; unfold G_Counter_merge; simpl;
    repeat rewrite ClockMapFacts.map2_1bis; auto.
    apply Clock_merge_idempotent.
    apply Clock_merge_idempotent.
Qed.

Theorem PN_Counter_merge_assoc : forall c1 c2 c3,
  PN_Counter_equal
    (PN_Counter_merge c1 (PN_Counter_merge c2 c3))
    (PN_Counter_merge (PN_Counter_merge c1 c2) c3).
Proof.
  intros.
  unfold PN_Counter_equal.
  split; unfold ClockMap.Equal; intros;
    unfold PN_Counter_merge; unfold G_Counter_merge; simpl;
    repeat rewrite ClockMapFacts.map2_1bis; auto;
    repeat rewrite <- Clock_merge_assoc; reflexivity.
Qed.

Theorem PN_Counter_incr_mono : forall clocks actor,
  PN_Counter_compare clocks (PN_Counter_incr actor clocks).
Proof.
  intros; unfold PN_Counter_compare; unfold PN_Counter_incr; simpl.
  split. apply G_Counter_incr_mono.
  apply G_Counter_compare_idempotent.
Qed.

Theorem PN_Counter_decr_mono : forall clocks actor,
  PN_Counter_compare clocks (PN_Counter_decr actor clocks).
Proof.
  intros; unfold PN_Counter_compare; unfold PN_Counter_decr; simpl.
  split. apply G_Counter_compare_idempotent.
  apply G_Counter_incr_mono.
Qed.

Theorem PN_Counter_merge_mono : forall c1 c2,
  PN_Counter_compare c1 (PN_Counter_merge c1 c2).
Proof.
  intros; unfold PN_Counter_compare; unfold PN_Counter_merge; split; simpl;
  apply G_Counter_merge_mono.
Qed.

(* 
   CRDT type, with CvRDT constructor.

   Defines the 4 basic operations on the CvRDT:
    merge, query, update and compare.

   States 5 facts about the CvRDT: merge is idempotent, commutative, and 
    associative, advances the lattice, 
    as well as the update function monotonically advancing.
*)

(* Check cons (G_Counter_incr, G_Counter_incr_mono). *)

(* list ((nat -> carrier -> carrier) * *)
(*       (forall clocks actor, compare clocks (update actor clocks))) -> *)
(* list ((nat -> carrier -> carrier) *  *)
(*       (forall clocks actor, compare clocks (update actor clocks))). *)
(*          ((ClockMap.key -> ClockMap.t nat -> ClockMap.t nat) * *)
(*           (forall (clocks : G_Counter) (actor : ClockMap.key), *)
(*            G_Counter_compare clocks (G_Counter_incr actor clocks))) *)

Record CRDT : Prop := CvRDT
                 {
                   carrier : Type;
                   merge : carrier -> carrier -> carrier;
                   query : carrier -> nat;
                   compare: carrier -> carrier -> Prop;
                   update: nat -> carrier -> carrier;
                   equal : carrier -> carrier -> Prop;
                   merge_idemp : forall x, equal (merge x x) x;
                   merge_comm : forall x y, equal (merge x y) (merge y x);
                   merge_assoc : forall x y z,
                                   equal (merge x (merge y z)) (merge (merge x y) z);
                   update_mono: forall x y, compare x (update y x);
                   merge_mono : forall x y, compare x (merge x y)
                 }.

Definition the_G_Counter := CvRDT
                  G_Counter
                  G_Counter_merge
                  G_Counter_reveal
                  G_Counter_compare
                  G_Counter_incr
                  G_Counter_equal
                  G_Counter_merge_idempotent
                  G_Counter_merge_comm
                  G_Counter_merge_assoc
                  G_Counter_incr_mono
                  G_Counter_merge_mono.

