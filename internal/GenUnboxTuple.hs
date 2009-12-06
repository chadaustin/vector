{-# LANGUAGE ParallelListComp #-}
module Main where

import Text.PrettyPrint

import System.Environment ( getArgs )

main = do
         [s] <- getArgs
         let n = read s
         mapM_ (putStrLn . render . generate) [2..n]

generate :: Int -> Doc
generate n =
  vcat [ data_instance "MVector s" "MV"
       , data_instance "Vector" "V"
       , class_instance "Unbox"
       , class_instance "M.MVector MVector" <+> text "where"
       , nest 2 $ vcat $ map method methods_MVector
       , class_instance "G.Vector Vector" <+> text "where"
       , nest 2 $ vcat $ map method methods_Vector
       ]

  where
    vars  = map char $ take n ['a'..]
    varss = map (<> char 's') vars
    tuple f = parens $ hsep $ punctuate comma $ map f vars
    vtuple f = parens $ sep $ punctuate comma $ map f vars
    con s = text s <> char '_' <> int n
    var c = text (c : "_")

    data_instance ty c
      = hang (hsep [text "data instance", text ty, tuple id])
             4
             (hsep [char '=', con c, text "{-# UNPACK #-} !Int"
                   , vcat $ map (\v -> parens (text ty <+> v)) vars])

    class_instance cls
      = text "instance" <+> vtuple (text "Unbox" <+>)
                        <+> text "=>" <+> text cls <+> tuple id


    pat c = parens $ con c <+> var 'n' <+> sep varss
    patn c n = parens $ con c <+> (var 'n' <> int n)
                              <+> sep [v <> int n | v <- varss]

    gen_length c = (pat c, var 'n')

    gen_unsafeSlice mod c
      = (pat c <+> var 'i' <+> var 'm',
         con c <+> var 'm'
               <+> vcat [parens $ text mod <> char '.' <> text "unsafeSlice"
                                  <+> vs <+> var 'i' <+> var 'm'
                                        | vs <- varss])


    gen_overlaps = (patn "MV" 1 <+> patn "MV" 2,
                    vcat $ r : [text "||" <+> r | r <- rs])
      where
        r : rs = [text "M.overlaps" <+> v <> char '1' <+> v <> char '2'
                        | v <- varss]

    gen_unsafeNew
      = (var 'n',
         mk_do [v <+> text "<- M.unsafeNew" <+> var 'n' | v <- varss]
               $ text "return $" <+> con "MV" <+> var 'n' <+> sep varss)

    gen_unsafeNewWith
      = (var 'n' <+> tuple id,
         mk_do [vs <+> text "<- M.unsafeNewWith" <+> var 'n' <+> v
                        | v  <- vars | vs <- varss]
               $ text "return $" <+> con "MV" <+> var 'n' <+> sep varss)

    gen_unsafeRead
      = (pat "MV" <+> var 'i',
         mk_do [v <+> text "<- M.unsafeRead" <+> vs <+> var 'i' | v  <- vars
                                                                | vs <- varss]
               $ text "return" <+> tuple id)

    gen_unsafeWrite
      = (pat "MV" <+> var 'i' <+> tuple id,
         mk_do [text "M.unsafeWrite" <+> vs <+> var 'i' <+> v | v  <- vars
                                                               | vs <- varss]
               empty)

    gen_clear
      = (pat "MV", mk_do [text "M.clear" <+> vs | vs <- varss] empty)

    gen_set
      = (pat "MV" <+> tuple id,
         mk_do [text "M.set" <+> vs <+> v | vs <- varss | v <- vars] empty)

    gen_unsafeCopy
      = (patn "MV" 1 <+> patn "MV" 2,
         mk_do [text "M.unsafeCopy" <+> vs <> char '1' <+> vs <> char '2'
                        | vs <- varss] empty)

    gen_unsafeGrow
      = (pat "MV" <+> var 'm',
         mk_do [text "M.unsafeGrow" <+> vs <+> var 'm' | vs <- varss]
               $ text "return $" <+> con "MV"
                                 <+> parens (var 'm' <> char '+' <> var 'n')
                                 <+> sep varss)

    gen_unsafeFreeze
      = (pat "MV",
         mk_do [vs <> char '\'' <+> text "<- G.unsafeFreeze" <+> vs
                        | vs <- varss]
               $ text "return $" <+> con "V" <+> var 'n'
                                 <+> sep [vs <> char '\'' | vs <- varss])

    gen_basicUnsafeIndexM
      = (pat "V" <+> var 'i',
         mk_do [v <+> text "<- G.basicUnsafeIndexM" <+> vs <+> var 'i'
                        | vs <- varss | v <- vars]
               $ text "return" <+> tuple id)

    
         

    mk_do cmds ret = hang (text "do")
                          2
                          $ vcat $ cmds ++ [ret]

    method (s, (p,e)) = text "{-# INLINE" <+> text s <+> text " #-}"
                     $$ hang (text s <+> p)
                             4
                             (char '=' <+> e)
                             

    methods_MVector = [("length",            gen_length "MV")
                      ,("unsafeSlice",       gen_unsafeSlice "M" "MV")
                      ,("overlaps",          gen_overlaps)
                      ,("unsafeNew",         gen_unsafeNew)
                      ,("unsafeNewWith",     gen_unsafeNewWith)
                      ,("unsafeRead",        gen_unsafeRead)
                      ,("unsafeWrite",       gen_unsafeWrite)
                      ,("clear",             gen_clear)
                      ,("set",               gen_set)
                      ,("unsafeCopy",        gen_unsafeCopy)
                      ,("unsafeGrow",        gen_unsafeGrow)]

    methods_Vector  = [("unsafeFreeze",      gen_unsafeFreeze)
                      ,("basicLength",       gen_length "V")
                      ,("basicUnsafeSlice",       gen_unsafeSlice "G" "V")
                      ,("basicUnsafeIndexM", gen_basicUnsafeIndexM)]