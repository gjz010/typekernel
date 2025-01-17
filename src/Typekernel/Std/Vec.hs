{-# LANGUAGE DataKinds, FlexibleInstances, FunctionalDependencies, UndecidableInstances, GeneralizedNewtypeDeriving, KindSignatures, TypeFamilies #-}
{-# LANGUAGE FlexibleContexts, ScopedTypeVariables #-}
module Typekernel.Std.Vec where
    import Typekernel.Structure
    import Typekernel.ProductType
    import Typekernel.Std.Basic
    import Typekernel.C4mAST
    import Typekernel.Transpiler
    import Typekernel.MLens
    import Typekernel.Nat
    import Data.Proxy
    import Control.Monad.Trans.Class
    import Control.Monad.Trans.Reader
    import Control.Monad
    import Typekernel.Memory
    import Typekernel.Constant
    import Typekernel.Vec
    import qualified Data.Vector as V
    data Buffer'

    -- Runtime buffer.
    type Buffer = Typedef Buffer' (Product (Basic UInt64) (Basic (Ptr UInt64)))

    bufSize :: (MonadC m)=>Buffer->m UInt64
    bufSize buffer=liftC $ do
        prod<-untypedef buffer
        value<-fstS prod
        mget basic value

    bufContent :: (MonadC m)=>Buffer->m (Ptr UInt64)
    bufContent buffer=liftC $ do
        prod<-untypedef buffer
        value<-sndS prod
        mget basic value

    sliceUnchecked :: (MonadC m, KnownNat n)=>Proxy n->UInt64->Buffer->m (Memory n)
    sliceUnchecked pn offset buf = liftC $ do
        ptr<-bufContent buf
        addr<-cast (Proxy :: Proxy UInt64) ptr
        oaddr<-binary opAdd addr offset
        optr<-cast (Proxy :: Proxy (Ptr UInt64)) oaddr
        return $ Memory optr

    newtype BufferParser m a = BufferParser {bpToReader :: ReaderT Buffer m a} deriving (Monad, Functor, Applicative, MonadTrans)
    instance (MonadC m)=>MonadC (BufferParser m) where
        liftC m=lift $ liftC m

    bufferOffset :: (MonadC m, KnownNat n)=>Proxy n->UInt64->BufferParser m (Memory n) 
    bufferOffset a b = BufferParser $ do
        buf<-ask
        lift $ sliceUnchecked a b buf
    
    readByte offset=do
        slice<-bufferOffset (Proxy :: Proxy N1) offset
        lift $ mget (byte (Proxy :: Proxy Z)) slice
    readHalf offset=do
        slice<-bufferOffset (Proxy :: Proxy N2) offset
        lift $ mget (half (Proxy :: Proxy Z)) slice
    readWord offset=do
        slice<-bufferOffset (Proxy :: Proxy N4) offset
        lift $ mget (word (Proxy :: Proxy Z)) slice
    readDword offset=do
        slice<-bufferOffset (Proxy :: Proxy N8) offset
        lift $ mget (dword (Proxy :: Proxy Z)) slice
    runBufferParser :: Buffer->BufferParser m a->m a
    runBufferParser buf parser = runReaderT (bpToReader parser) buf
    

    -- Fixed-sized array.
    {-
    data Array' (s::Nat) a

    type family Array (s::Nat) a where
        Array Z _=Proxy (Array' Z)
        Array N1 a = Typedef (Array' N1 a) a
        Array (S x) a = Typedef (Array' (S x) a) (Product a (Array x a))

    class ArrayIndexable m arr a (s::Nat)  | arr->s, arr->a where
        unsafeIndex :: arr->Int->m a
        

    instance (MonadC m)=>ArrayIndexable m (Proxy (Array' Z a)) a Z where
        unsafeIndex = error "Can't index into zero-sized array! Luckily enough, this access should be stopped by compiler..."
    
    instance (MonadC m, KnownNat n, Structure n a, SizeOf a ~ n)=>ArrayIndexable m (Typedef (Array' N1 a) a) a N1 where
        unsafeIndex arr _ = liftC $ untypedef arr

    instance (MonadC m, ArrayIndexable m arr a s, Structure m0 a, SizeOf a ~ m0, KnownNat m0, KnownNat n0, Structure n0 arr, SizeOf arr ~ n0)=> ArrayIndexable m (Typedef (Array' (S s) a) (Product a arr)) a (S s) where
        -- This approach is low in efficiency: need hard constant propagation.
        unsafeIndex arr index= 
            if (index == 0) then 
                liftC $ do
                    prod<-untypedef arr
                    fstS prod
            else do
                    prod<-liftC $ untypedef arr
                    subarray<-liftC $ sndS prod
                    subarray `unsafeIndex` (index-1)


            
    (!!:) :: (ArrayIndexable m arr a (s::Nat), KnownNat (idx::Nat), PeanoLT idx s True)=>arr->Proxy idx->m a
    (!!:) arr p = unsafeIndex arr (natToInt p)


    rightArr :: Proxy (Typedef (Array' (S s) a) (Product a arr)) -> Proxy arr
    rightArr =const Proxy
    class ArrayCtor m arr a (s::Nat) (n::Nat)  | arr->s, arr->n, arr->a where
        unsafeCtorArray ::  Proxy arr->[Memory n->m a]->Memory (NMul s n)->m arr
    instance (MonadC m, Structure n a, SizeOf a ~ n)=>ArrayCtor m (Proxy (Array' Z a)) a Z n where
        unsafeCtorArray _ _ _=return Proxy
    instance (MonadC m, KnownNat n, Structure n a, SizeOf a ~ n, NMul N1 n ~ n)=>ArrayCtor m (Typedef (Array' N1 a) a) a N1 n where
        unsafeCtorArray _ (ctor:ctors)= ctorNewtype ctor
    instance (MonadC m, KnownNat n, Structure n a, SizeOf a ~ n, ArrayCtor m arr a s n,
             Structure n0 arr, SizeOf arr ~ n0, 
             NAdd s 1 ~ ss, 
             NMul s n ~ n0, NMul ss n ~ NAdd (NUpRound8 n) (NUpRound8 n0),
             KnownNat n0, (KnownNat (NAdd (NUpRound8 n) (NUpRound8 n0))))
             =>ArrayCtor m (Typedef (Array' ss a) (Product a arr)) a ss n where
        unsafeCtorArray pa (ctor:ctors) =
            let ctorleft=ctor
                ctorright=unsafeCtorArray (rightArr pa) ctors
                ctorp=ctorProd ctorleft ctorright
                ctorn=ctorNewtype ctorp
            in ctorn
    ctorArray :: (ArrayCtor m arr a (s::Nat) (n::Nat), Array s a ~ arr)=>Vec (Memory n->m a) s->Memory (NMul s n)->m arr
    ctorArray vec = unsafeCtorArray Proxy (toListV vec)
    -}


    data StaticArray (s::Nat) a = StaticArray {staticArrayToMem :: Memory (NMul s (SizeOf a))}
    

    instance (Structure n a, SizeOf a ~ n, NMul s n ~ sn)=>Structure sn (StaticArray s a) where
        --restore :: Proxy (StaticArray s a)->(Memory sn)->C (StaticArray s a)
        restore _ memory = return $ StaticArray memory
    
    (!!:) :: (MonadC m, Structure n a, SizeOf a ~ n, NMul s n ~ sn, PeanoLT (t::Nat) s True, KnownNat s, KnownNat n, KnownNat t)=>Proxy t->(StaticArray s a)->m a
    (!!:) (p :: Proxy t) (arr :: StaticArray s a)= do
        let memory=staticArrayToMem arr :: Memory (NMul s (SizeOf a))
        let offset_obj=natToInt p
        let size_obj=natToInt (Proxy :: Proxy (SizeOf a))
        offset_total<-liftC $ immUInt64 $ fromIntegral (size_obj*offset_obj)
        slice<-liftC $ unsafeSubmemory' (offset_total, (Proxy :: Proxy (SizeOf a))) memory
        liftC $ restore Proxy slice

    instance (Lifetime a m, MonadC m, Structure n a, SizeOf a ~ n, NMul s n ~ sn, KnownNat s, KnownNat n, Structure n a)=>Lifetime (StaticArray s a) m where
        finalize (arr :: StaticArray s a) = do
            let element_count=natToInt (Proxy :: Proxy s)
            sequence_ [(do
                let memory=staticArrayToMem arr :: Memory (NMul s (SizeOf a))
                let offset_obj=x
                let size_obj=natToInt (Proxy :: Proxy (SizeOf a))
                offset_total<-liftC $ immUInt64 $ fromIntegral (size_obj*offset_obj)
                slice<-liftC $ unsafeSubmemory' (offset_total, (Proxy :: Proxy (SizeOf a))) memory
                subobj<-liftC $ restore (Proxy :: Proxy a) slice
                finalize subobj
                )|x<-[0..element_count-1]]

    ctorArray :: (MonadC m, Structure n a, SizeOf a ~ n, NMul s n ~ sn, KnownNat s, KnownNat n)=>
                    Vec (Memory n->m a) s->Memory sn->m (StaticArray s a)
    ctorArray (vec :: Vec (Memory n->m a) s) (memory :: Memory sn) = do
        let element_count = natToInt (Proxy :: Proxy s)
        sequence_ [(do
            let offset_obj=x
            let size_obj=natToInt (Proxy :: Proxy (SizeOf a))
            offset_total<-liftC $ immUInt64 $ fromIntegral (size_obj*offset_obj)
            slice<-liftC $ unsafeSubmemory' (offset_total, (Proxy :: Proxy (SizeOf a))) memory
            let ctor=(V.!) (getVector vec) offset_obj
            ctor slice
            )|x<-[0..element_count-1]]
        return $ StaticArray memory

    type instance (SizeOf (StaticArray s a))=NMul s (SizeOf a)

    data BasicMem' (n::Nat)
    type BasicMem (n::Nat)=Typedef (BasicMem' n) (StaticArray (NCeil8 (NUpRound8 n)) (Basic UInt64))

    