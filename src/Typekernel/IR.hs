{-# LANGUAGE DeriveGeneric, FunctionalDependencies, FlexibleInstances #-}
module Typekernel.IR where
    import GHC.Generics
    import Data.Aeson
    import Typekernel.C4mAST
    import Typekernel.Nat
    import Debug.Trace
    import Data.Word
    import qualified Data.ByteString.Lazy as BS
    data IRDatatype=IInt8 | IUInt8 | IInt16 | IUInt16 | IInt32 | IUInt32 | IInt64 | IUInt64   deriving (Generic, Show)
    data IRLiteral = IInteger Integer deriving (Generic, Show)
    
    data IRStmt =
        IRExternFun {
            iName :: String,
            iReturnType :: IRDatatype,
            iArgumentType :: [IRDatatype]
        } |
        IRFun {
            iName :: String,
            iReturnField :: (IRDatatype, String),
            iArgumentField :: [(IRDatatype, String)],
            iFuncBody :: [IRStmt]
        } |
        IRImm {
            iUName :: (IRDatatype, String),
            iLiteral :: String
        } |
        {-
            Possible values: [
                ("Add", "+"), 
                ("Sub", "-"), 
                ("Mul", "*"), 
                ("Div", "/"), 
                ("Mod", "%"), 
                ("Xor", "^"), 
                ("Or", "|"), 
                ("And", "&"), 
                ("CEQ", "=="), 
                ("CLT", "<"), 
                ("CGT", ">"),
                ("CLE", "<="),
                ("CGE", ">="),
                ("CNE", "!="),
                ("LShift", "<<"),
                ("RShift", ">>")]
        -}
        IRBinary {
            iUName :: (IRDatatype, String),
            iOperator :: String,
            iOperand1 :: String,
            iOperand2 :: String
        } | 
        {- 
            Possible values: ("Invert", "~"),
                             ("Neg", "-"),
                             ("Not", "!"),  
        -}
        IRUnary {
            iUName :: (IRDatatype, String),
            iOperator :: String,
            iOperand ::  String
        } |
        IRInvoke {
            iInvokedFun :: String,
            iUName :: (IRDatatype, String),
            iArguments :: [String]
        } |
        IRTernary {
            iLName :: [(IRDatatype, String)],
            iTOperand1 :: String,
            -- Pairs of statements and returned names.
            iTOperand2 :: ([IRStmt], [String]),
            -- Pairs of statements and returned names.
            iTOperand3 :: ([IRStmt], [String])
        } |
        IRCast {
            iUName :: (IRDatatype, String),
            iOperand :: String
        } |
        -- Allocate a given size of memory on stack. The result will always be (Ptr UInt64).
        -- The size is used as some hint.
        IRAlloca {
            iName :: String,
            iMemSize :: Int
        } |
        -- Give hint on a pointer about its size. The operation will always be performed on (Ptr UInt64).
        -- Ignoring the hint will not cause a failure, but using the hint helps make a more precise pointer reference analysis.
        IRMemoryHint {
            iName ::String,
            iMemSize :: Int
        } |
        IRMemcpy {
            iMemSize :: Int,
            iDest :: String,
            iSource :: String
        } |
        IRDeref {
            iDest :: String,
            iSource :: String
        } |
        IRModifyRef {
            iDest :: String,
            iSource :: String
        } |
        IRStringLiteral {
            iName :: String,
            iStringLiteral :: String
        }
        deriving (Generic, Show)

    type Program = ([String], [IRStmt])
    compileProgram :: Program->String
    compileProgram = (map (toEnum.fromIntegral).(BS.unpack)) . encode
    instance ToJSON IRDatatype
    instance FromJSON IRDatatype
    instance ToJSON IRLiteral
    instance FromJSON IRLiteral
    instance ToJSON IRStmt
    instance FromJSON IRStmt

    class IRDatatypeCast a b | a->b where
        castDatatype :: a->(b, String)

    typeToName :: String->IRDatatype
    typeToName "int8_t"=IInt8
    typeToName "uint8_t"=IUInt8
    typeToName "int16_t"=IInt16
    typeToName "uint16_t"=IUInt16
    typeToName "int32_t"=IInt32
    typeToName "uint32_t"=IUInt32
    typeToName "int64_t"=IInt64
    typeToName "uint64_t"=IUInt64
    typeToName x = trace ("Warning: unknown datatype "++x++". Falling back to uint64_t.") IUInt64
