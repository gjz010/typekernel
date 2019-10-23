{-# LANGUAGE DataKinds, FlexibleInstances, FunctionalDependencies, UndecidableInstances, RankNTypes #-}
module Typekernel.Std.Basic where
    import Typekernel.C4mAST
    import Typekernel.Transpiler
    import Typekernel.Structure
    import Typekernel.Nat
    import Data.Proxy
    import Typekernel.Memory
    import Typekernel.MLens
    import Control.Monad.Trans.Class
    import Control.Monad.Fix
    import Typekernel.Array
    data Basic a=Basic {basicVal :: Memory N8}

    instance (Monad m)=>Lifetime a m

    instance (FirstClass a)=>Structure N8 (Basic a) where
        restore _=return . Basic
    
    basic :: (FirstClass a)=>Proxy a->MLens C (Basic a) a
    basic pa= mkMLens getter setter where
                getter mem = do
                    let (Memory ptr)=basicVal mem
                    let ppa=promotePtr pa
                    ptra<-cast ppa ptr
                    deref ptra
                setter mem v= do
                    let (Memory ptr)=basicVal mem
                    let ppa=promotePtr pa
                    ptra<-cast ppa ptr
                    mref ptra v

    zeroBasic :: Proxy a->Memory N8->C (Basic a)
    zeroBasic pa mem = do
        let b=Basic mem
        zero<-immUInt64 0
        mset (basic (Proxy :: Proxy UInt64)) b zero
        return $ Basic mem