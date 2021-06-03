{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE KindSignatures        #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE RankNTypes            #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
{-# LANGUAGE UndecidableInstances  #-}
{-# OPTIONS_GHC -fno-warn-redundant-constraints #-}

-- | This module provides typeclasses for describing protobuf service metadata.
-- It is intended to be used by library authors to generating bindings against
-- proto services for specific RPC backends.
module Data.ProtoLens.Service.Types
  ( Service (..)
  , HasAllMethods
  , HasMethodImpl (..)
  , HasMethod
  , StreamingType (..)
  ) where

import qualified Data.ByteString as B
import Data.Kind (Constraint)
import Data.ProtoLens.Message (Message)
import Data.Proxy (Proxy(..))
import GHC.TypeLits


-- | Reifies the fact that there is a 'HasMethod' instance for every symbol
-- claimed by the 'ServiceMethods' associated type.
class HasAllMethods s (ms :: [Symbol])
instance HasAllMethods s '[]
instance (HasAllMethods s ms, HasMethodImpl s m) => HasAllMethods s (m ': ms)


-- | Metadata describing a protobuf service. The 's' parameter is a phantom
-- type generated by proto-lens.
--
-- The 'ServiceName' and 'ServicePackage' associated type can be used to
-- generate RPC endpoint paths.
--
-- 'ServiceMethods' is a promoted list containing every method defined on the
-- service. As witnessed by the 'HasAllMethods' superclass constraint here,
-- this type can be used to discover every instance of 'HasMethod' available
-- for the service.
class ( KnownSymbol (ServiceName s)
      , KnownSymbol (ServicePackage s)
      , HasAllMethods s (ServiceMethods s)
      ) => Service s where
  type ServiceName s    :: Symbol
  type ServicePackage s :: Symbol
  type ServiceMethods s :: [Symbol]

  packedServiceDescriptor :: Proxy s -> B.ByteString

------------------------------------------------------------------------------
-- | Data type to be used as a promoted type for 'MethodStreamingType'.
data StreamingType
  = NonStreaming
  | ClientStreaming
  | ServerStreaming
  | BiDiStreaming
  deriving (Eq, Ord, Enum, Bounded, Read, Show)


-- | Metadata describing a service method. The 'MethodInput' and 'MethodOutput'
-- type families correspond to the 'Message's generated by proto-lens for the
-- RPC as described in the protobuf.
--
-- 'IsClientStreaming' and 'IsServerStreaming' can be used to dispatch on
-- library code which wishes to provide different interfaces depending on the
-- type of streaming of the method.
--
-- Library code should use 'HasMethod' instead of this class directly whenever
-- the constraint will be exposed to the end user. 'HasMethod' provides
-- substantially friendlier error messages when used incorrectly.
class ( KnownSymbol m
      , KnownSymbol (MethodName s m)
      , Service s
      , Message (MethodInput  s m)
      , Message (MethodOutput s m)
      ) => HasMethodImpl s (m :: Symbol) where
  type MethodName          s m :: Symbol
  type MethodInput         s m :: *
  type MethodOutput        s m :: *
  type MethodStreamingType s m :: StreamingType


-- | Helper constraint that expands to a user-friendly error message when 'm'
-- isn't actually a method provided by service 's'.
type HasMethod s m =
  ( RequireHasMethod s m (ListContains m (ServiceMethods s))
  , HasMethodImpl s m
  )


-- | Outputs an error message saying that the given method wasn't found, and
-- suggests alternatives the user might have wanted.
type family RequireHasMethod s (m :: Symbol) (h :: Bool) :: Constraint where
  RequireHasMethod s m 'False = TypeError
       ( 'Text "No method "
   ':<>: 'ShowType m
   ':<>: 'Text " available for service '"
   ':<>: 'ShowType s
   ':<>: 'Text "'."
   ':$$: 'Text "Available methods are: "
   ':<>: ShowList (ServiceMethods s)
       )
  RequireHasMethod s m 'True = ()


-- | Expands to 'True' when 'n' is in promoted list 'hs', 'False' otherwise.
type family ListContains (n :: k) (hs :: [k]) :: Bool where
  ListContains n '[]       = 'False
  ListContains n (n ': hs) = 'True
  ListContains n (x ': hs) = ListContains n hs


-- | Pretty prints a promoted list.
type family ShowList (ls :: [k]) :: ErrorMessage where
  ShowList '[]  = 'Text ""
  ShowList '[x] = 'ShowType x
  ShowList (x ': xs) =
    'ShowType x ':<>: 'Text ", " ':<>: ShowList xs

