module SyntaxSpec (syntaxSpec) where

import Lib
  ( Context(..)
  , EffectMap(..)
  , Row(..)
  , TermVar(..)
  , Type(..)
  , TypeVar(..)
  , contextLookupType
  , effectMapLookup )
import Test.Hspec (Spec, describe, it)
import Test.Hspec.Core.QuickCheck (modifyMaxSuccess)
import Test.QuickCheck (property)

-- The QuickCheck specs

specContextLookupAfterExtend :: Context -> TermVar -> Type -> Row -> Bool
specContextLookupAfterExtend c x t r =
  contextLookupType (CTExtend c x t r) x == Just (t, r)

specContextExtendAfterLookup :: Context -> TermVar -> TermVar -> Bool
specContextExtendAfterLookup c x1 x2 = case contextLookupType c x1 of
  Just (t, r) ->
    contextLookupType (CTExtend c x1 t r) x2 == contextLookupType c x2
  Nothing -> True

specEffectMapLookupAfterExtend :: EffectMap -> TypeVar -> Type -> Row -> Bool
specEffectMapLookupAfterExtend em a t r =
  effectMapLookup (EMExtend em a t r) a == Just (t, r)

specEffectMapExtendAfterLookup :: EffectMap -> TypeVar -> TypeVar -> Bool
specEffectMapExtendAfterLookup em a1 a2 = case effectMapLookup em a1 of
  Just (t, r) ->
    effectMapLookup (EMExtend em a1 t r) a2 == effectMapLookup em a2
  Nothing -> True

syntaxSpec :: Spec
syntaxSpec = modifyMaxSuccess (const 100000) $ do
  describe "contextLookupType" $ do
    it "contextLookupType (CTExtend c x t r) x == Just (t, r)"
      $ property specContextLookupAfterExtend
    it "CTExtend em x t r == CTExtend (contextLookupType em x) x t r"
      $ property specContextExtendAfterLookup
  describe "effectMapLookup" $ do
    it "effectMapLookup (EMExtend em a t r) a == Just (t, r)"
      $ property specEffectMapLookupAfterExtend
    it "EMExtend em a t r == em where effectMapLookup em a = Just (t, r)"
      $ property specEffectMapExtendAfterLookup
