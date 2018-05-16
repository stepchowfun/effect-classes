{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- The algorithm presented here is based on the paper by Daan Leijen called
-- "HMF: Simple type inference for first-class polymorphism". That paper was
-- published in The 13th ACM SIGPLAN International Conference on Functional
-- Programming (ICFP 2008).
module Inference
  ( typeCheck
  ) where

import Control.Monad (foldM, replicateM, when)
import Control.Monad.Except (ExceptT, runExceptT, throwError)
import Control.Monad.State (State, evalState, get, put)
import Data.List (nub)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Substitution
  ( Substitution
  , applySubst
  , composeSubst
  , emptySubst
  , singletonSubst
  , substRemoveKeys
  )
import Syntax
  ( BForAll(..)
  , EVarName(..)
  , FTerm(..)
  , ITerm(..)
  , TConName(..)
  , TVarName(..)
  , Type(..)
  , arrowName
  , arrowType
  , boolName
  , boolType
  , collectBinders
  , freeTCons
  , freeTVars
  , intName
  , intType
  , listName
  , listType
  , subst
  )

-- The TypeCheck monad provides:
-- 1. The ability to generate fresh variables (via State)
-- 1. The ability to read and update the context (also via State)
-- 2. The ability to throw errors (via ExceptT)
type TypeCheck
   = ExceptT String (State ( Integer
                           , Map EVarName Type
                           , Set TVarName
                           , Map TConName Integer))

-- Add a term variable to the context.
withUserEVar :: EVarName -> Type -> TypeCheck a -> TypeCheck a
withUserEVar x t k = do
  (i1, cx1, ca1, cc1) <- get
  when (Map.member x cx1) $ throwError $ "Variable already exists: " ++ show x
  put (i1, Map.insert x t cx1, ca1, cc1)
  result <- k
  (i2, cx2, ca2, cc2) <- get
  put (i2, Map.delete x cx2, ca2, cc2)
  return result

-- Generate a fresh type variable and add it to the context.
freshTVar :: TypeCheck TVarName
freshTVar = do
  (i, cx, ca, cc) <- get
  let a = AutoTVarName i
  put (i + 1, cx, Set.insert a ca, cc)
  return a

-- Generate a fresh type constructor and add it to the context.
freshTCon :: Integer -> TypeCheck TConName
freshTCon n = do
  (i, cx, ca, cc) <- get
  let c = AutoTConName i
  put (i + 1, cx, ca, Map.insert c n cc)
  return c

-- Substitute a type for a type variable in the context.
substInContext :: TVarName -> Type -> TypeCheck ()
substInContext a t = do
  (i, cx, ca, cc) <- get
  put (i, Map.map (subst a t) cx, ca, cc)

-- Compute the most general unifier of two types. The returned substitution is
-- also applied to the context.
unify :: Type -> Type -> TypeCheck Substitution
unify (TVar a1) (TVar a2)
  | a1 == a2 = return emptySubst
unify (TVar a) t
  | a `notElem` freeTVars t = do
    substInContext a t
    return $ singletonSubst a t
unify t (TVar a)
  | a `notElem` freeTVars t = do
    substInContext a t
    return $ singletonSubst a t
unify t1@(TCon c1 ts1) t2@(TCon c2 ts2)
  | c1 == c2 = do
    if length ts1 == length ts2
      then return ()
      else throwError $ "Unable to unify " ++ show t1 ++ " with " ++ show t2
    foldM
      (\theta1 (t3, t4) -> do
         theta2 <- unify (applySubst theta1 t3) (applySubst theta1 t4)
         return $ composeSubst theta1 theta2)
      emptySubst
      (zip ts1 ts2)
unify t3@(TForAll a1 t1) t4@(TForAll a2 t2) = do
  c <- freshTCon 0
  theta <- unify (subst a1 (TCon c []) t1) (subst a2 (TCon c []) t2)
  if c `elem` freeTCons theta
    then throwError $ "Unable to unify " ++ show t3 ++ " with " ++ show t4
    else return theta
unify t1 t2 =
  throwError $ "Unable to unify " ++ show t1 ++ " with " ++ show t2

-- Instantiate, generalize, and unify as necessary to make a given term and
-- type match another given type. The returned substitution is also applied to
-- the context.
subsume :: FTerm -> Type -> Type -> TypeCheck (FTerm, Substitution)
subsume e1 t1 t2 = do
  let (BForAll as1, t3) = collectBinders t1
      (BForAll as2, t4) = collectBinders t2
  as3 <- replicateM (length as1) freshTVar
  cs1 <- replicateM (length as2) (freshTCon 0)
  let e3 = foldr (\a e2 -> FETApp e2 (TVar a)) e1 as3
      t5 = foldr (\(a1, a2) -> subst a1 (TVar a2)) t3 (zip as1 as3)
      t6 = foldr (\(a, c) -> subst a (TCon c [])) t4 (zip as2 cs1)
  theta1 <- unify t5 t6
  let theta2 = substRemoveKeys (Set.fromList as3) theta1
  if Set.null $
     Set.intersection (Set.fromList cs1) (Set.fromList $ freeTCons theta2)
    then return ()
    else throwError $ show t2 ++ " is not subsumed by " ++ show t1
  as4 <- replicateM (length cs1) freshTVar
  let e5 =
        foldr
          (\(c, a) e4 -> FETAbs a (subst c (TVar a) e4))
          (applySubst theta1 e3)
          (zip cs1 as4)
  return (e5, theta2)

-- Generalize a term and a type.
generalize :: FTerm -> Type -> TypeCheck (FTerm, Type)
generalize e1 t1 = do
  (_, cx, _, _) <- get
  let cfv = Set.fromList $ Map.foldr (\t2 as -> freeTVars t2 ++ as) [] cx
      tfv = filter (`Set.notMember` cfv) $ nub $ freeTVars e1 ++ freeTVars t1
  return (foldr FETAbs e1 tfv, foldr TForAll t1 tfv)

-- Instantiate outer universal quantifiers with fresh type variables.
open :: FTerm -> Type -> TypeCheck (FTerm, Type)
open e (TForAll a1 t) = do
  a2 <- freshTVar
  open (FETApp e (TVar a2)) (subst a1 (TVar a2) t)
open e t = return (e, t)

-- A helper method for checking a term against a type.
check :: ITerm -> Type -> TypeCheck (FTerm, Type, Substitution)
check e1 t1 = do
  (e2, t2, theta1) <- infer e1
  (e3, theta2) <- subsume e2 t2 (applySubst theta1 t1)
  let theta3 = composeSubst theta1 theta2
  return (e3, applySubst theta3 t1, theta3)

-- A helper method for type checking binary operations (e.g., arithmetic
-- operations).
checkBinary ::
     ITerm
  -> Type
  -> ITerm
  -> Type
  -> TypeCheck (FTerm, Type, FTerm, Type, Substitution)
checkBinary e1 t1 e2 t2 = do
  (e3, t3, theta1) <- check e1 t1
  (e4, t4, theta2) <- check e2 (applySubst theta1 t2)
  return
    ( applySubst theta2 e3
    , applySubst theta2 t3
    , e4
    , t4
    , composeSubst theta1 theta2)

-- Replace all variables in a type (both free and bound) with fresh type
-- variables. This is used to sanitize type annotations, which would otherwise
-- be subject to issues related to variable capture (e.g., in type
-- applications). Note that "free" variables in type annotations are implicitly
-- existentially bound, so they are not really free (and thus we are justified
-- in renaming them).
sanitizeAnnotation :: Type -> TypeCheck Type
sanitizeAnnotation t1 =
  let fv = freeTVars t1
  in do t2 <-
          foldM
            (\t2 a1 -> do
               a2 <- freshTVar
               return (subst a1 (TVar a2) t2))
            t1
            fv
        replaceBoundVars t2
  where
    replaceBoundVars t2@(TVar _) = return t2
    replaceBoundVars (TCon c ts1) = do
      ts2 <- mapM replaceBoundVars ts1
      return $ TCon c ts2
    replaceBoundVars (TForAll a1 t2) = do
      a2 <- freshTVar
      t3 <- replaceBoundVars (subst a1 (TVar a2) t2)
      return $ TForAll a2 t3

-- Infer the type of a term. Inference may involve unification. This function
-- returns a substitution which is also applied to the context.
infer :: ITerm -> TypeCheck (FTerm, Type, Substitution)
infer (IEVar x) = do
  (_, cx, _, _) <- get
  case Map.lookup x cx of
    Just t -> return (FEVar x, t, emptySubst)
    Nothing -> throwError $ "Undefined variable: " ++ show x
infer (IEAbs x t1 e1) = do
  t2 <-
    case t1 of
      Just t2 -> sanitizeAnnotation t2
      Nothing -> TVar <$> freshTVar
  (e2, t3, theta) <-
    withUserEVar x t2 $ do
      (e2, t3, theta) <- infer e1
      let t4 = applySubst theta t2
      case (t2, t4) of
        (TForAll _ _, _) -> return ()
        (_, TForAll _ _) ->
          throwError $ "Inferred polymorphic argument type: " ++ show t4
        _ -> return ()
      (e3, t5) <- open e2 t3
      return (FEAbs x t4 e3, arrowType t4 t5, theta)
  (e3, t4) <- generalize e2 t3
  return (e3, t4, theta)
infer (IEApp e1 e2) = do
  a1 <- freshTVar
  a2 <- freshTVar
  (e3, t1, theta1) <- check e1 $ arrowType (TVar a1) (TVar a2)
  let (t4, t5) =
        case t1 of
          TCon c [t2, t3]
            | c == arrowName -> (t2, t3)
          _ -> error "Something went wrong."
  (e4, _, theta2) <- check e2 t4
  (e5, t6) <-
    generalize (FEApp (applySubst theta2 e3) e4) (applySubst theta2 t5)
  return (e5, t6, composeSubst theta1 theta2)
infer (IELet x e1 e2) = do
  (e3, t1, theta1) <- infer e1
  withUserEVar x t1 $ do
    (e4, t2, theta2) <- infer e2
    return
      ( FEApp (FEAbs x (applySubst theta2 t1) e4) (applySubst theta2 e3)
      , t2
      , composeSubst theta1 theta2)
infer (IEAnno e1 t1) = do
  t2 <- sanitizeAnnotation t1
  (e2, t3, theta) <- check e1 t2
  (e3, t4) <- generalize e2 t3
  return (e3, t4, theta)
infer IETrue = return (FETrue, boolType, emptySubst)
infer IEFalse = return (FEFalse, boolType, emptySubst)
infer (IEIf e1 e2 e3) = do
  (e4, _, theta1) <- check e1 boolType
  t1 <- TVar <$> freshTVar
  (e5, t2, e6, _, theta2) <- checkBinary e2 t1 e3 t1
  (e7, t3) <- generalize (FEIf (applySubst theta2 e4) e5 e6) t2
  return (e7, t3, composeSubst theta1 theta2)
infer (IEIntLit i) = return (FEIntLit i, intType, emptySubst)
infer (IEAdd e1 e2) = do
  (e3, _, e4, _, theta) <- checkBinary e1 intType e2 intType
  (e5, t) <- generalize (FEAdd e3 e4) intType
  return (e5, t, theta)
infer (IESub e1 e2) = do
  (e3, _, e4, _, theta) <- checkBinary e1 intType e2 intType
  (e5, t) <- generalize (FESub e3 e4) intType
  return (e5, t, theta)
infer (IEMul e1 e2) = do
  (e3, _, e4, _, theta) <- checkBinary e1 intType e2 intType
  (e5, t) <- generalize (FEMul e3 e4) intType
  return (e5, t, theta)
infer (IEDiv e1 e2) = do
  (e3, _, e4, _, theta) <- checkBinary e1 intType e2 intType
  (e5, t) <- generalize (FEDiv e3 e4) intType
  return (e5, t, theta)
infer (IEList es1) = do
  t1 <- TVar <$> freshTVar
  (es2, theta) <-
    foldM
      (\(es2, theta1) e1 -> do
         (e2, _, theta2) <- check e1 (applySubst theta1 t1)
         return (e2 : (applySubst theta2 <$> es2), composeSubst theta1 theta2))
      ([], emptySubst)
      es1
  (e, t2) <-
    generalize (FEList $ reverse es2) (listType (applySubst theta t1))
  return (e, t2, theta)
infer (IEConcat e1 e2) = do
  t1 <- listType . TVar <$> freshTVar
  (e3, t2, e4, _, theta) <- checkBinary e1 t1 e2 t1
  (e5, t3) <- generalize (FEConcat e3 e4) t2
  return (e5, t3, theta)

-- Type inference can generate superfluous type abstractions and applications.
-- This function removes them. The simplification is type-preserving.
simplify :: FTerm -> FTerm
simplify e@(FEVar _) = e
simplify (FEAbs x t e) = FEAbs x t (simplify e)
simplify (FEApp e1 e2) = FEApp (simplify e1) (simplify e2)
simplify (FETAbs a1 (FETApp e (TVar a2)))
  | a1 == a2 && a1 `notElem` freeTVars e = e
simplify (FETAbs a e) = FETAbs a (simplify e)
simplify (FETApp (FETAbs a e) t) = simplify (subst a t e)
simplify (FETApp e t) = FETApp (simplify e) t
simplify e@(FEIntLit _) = e
simplify (FEAdd e1 e2) = FEAdd (simplify e1) (simplify e2)
simplify (FESub e1 e2) = FESub (simplify e1) (simplify e2)
simplify (FEMul e1 e2) = FEMul (simplify e1) (simplify e2)
simplify (FEDiv e1 e2) = FEDiv (simplify e1) (simplify e2)
simplify FETrue = FETrue
simplify FEFalse = FEFalse
simplify (FEIf e1 e2 e3) = FEIf (simplify e1) (simplify e2) (simplify e3)
simplify (FEList es) = FEList $ simplify <$> es
simplify (FEConcat e1 e2) = FEConcat (simplify e1) (simplify e2)

-- Given a term in the untyped language, return a term in the typed language
-- together with its type.
typeCheck :: ITerm -> Either String (FTerm, Type)
typeCheck e1 =
  let result =
        evalState
          (runExceptT (infer e1))
          ( 0
          , Map.empty
          , Set.empty
          , Map.fromList [(boolName, 0), (intName, 0), (listName, 1)])
  in case result of
       Left s -> Left s
       Right (e2, t, _) -> Right (simplify e2, t)
