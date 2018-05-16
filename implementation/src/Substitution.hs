module Substitution
  ( ApplySubst
  , Substitution
  , applySubst
  , composeSubst
  , emptySubst
  , singletonSubst
  , substRemoveKeys
  ) where

import Data.List (nub)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Syntax
  ( FTerm(..)
  , FreeTCons
  , FreeTVars
  , TVarName(..)
  , Type(..)
  , freeTCons
  , freeTVars
  , subst
  )

-- A substitution maps type variables to types. We maintain the invariant that
-- all substitutions are idempotent.
newtype Substitution =
  Substitution (Map TVarName Type)

-- The free type variables of the codomain of a substitution
instance FreeTVars Substitution where
  freeTVars (Substitution m) =
    nub $ Map.foldr (\t as -> freeTVars t ++ as) [] m

-- The free type constructors of the codomain of a substitution
instance FreeTCons Substitution where
  freeTCons (Substitution m) =
    nub $ Map.foldr (\t cs -> freeTCons t ++ cs) [] m

-- Check that a substitution is idempotent.
idempotencyCheck :: Substitution -> Substitution
idempotencyCheck theta@(Substitution m) =
  if Set.null $
     Map.keysSet m `Set.intersection` Set.fromList (freeTVars theta)
    then theta
    else error $ "Non-idempotent substitution: " ++ show m

-- Construct an empty substitution.
emptySubst :: Substitution
emptySubst = Substitution Map.empty

-- Construct a substitution from a type variable and a type.
singletonSubst :: TVarName -> Type -> Substitution
singletonSubst a t = idempotencyCheck $ Substitution $ Map.singleton a t

-- Compose two substitutions. The substitutions are in diagrammatic order, that
-- is, theta2 comes after theta1.
composeSubst :: Substitution -> Substitution -> Substitution
composeSubst (Substitution m1) theta@(Substitution m2) =
  idempotencyCheck $
  Substitution $ Map.union m2 (Map.map (applySubst theta) m1)

-- Remove keys from a substitution.
substRemoveKeys :: Set TVarName -> Substitution -> Substitution
substRemoveKeys as (Substitution m) = Substitution $ Map.withoutKeys m as

-- Substitutions can be applied to various entities.
class ApplySubst a where
  applySubst :: Substitution -> a -> a

-- We deliberately omit an ApplySubst ITerm instance. The only free type
-- variables of an ITerm come from type annotations, but free type variables in
-- annotations are interpreted as implicitly existentially bound (i.e., they
-- aren't really free).
instance ApplySubst FTerm where
  applySubst (Substitution m) e = Map.foldrWithKey subst e m

instance ApplySubst Type where
  applySubst (Substitution m) t = Map.foldrWithKey subst t m
