import Debug.Trace

-- TP-1  --- Implantation d'une sorte de Lisp          -*- coding: utf-8 -*-
{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use camelCase" #-}
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}
{-# HLINT ignore "Redundant bracket" #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}
{-# HLINT ignore "Use id" #-}
{-# HLINT ignore "Use const" #-}
{-# HLINT ignore "Use record patterns" #-}
{-# HLINT ignore "Replace case with maybe" #-}
{-# OPTIONS_GHC -Wno-overlapping-patterns #-}
--
-- Ce fichier défini les fonctionalités suivantes:
-- - Analyseur lexical
-- - Analyseur syntaxique
-- - Pretty printer
-- - Implantation du langage

---------------------------------------------------------------------------
-- Importations de librairies et définitions de fonctions auxiliaires    --
---------------------------------------------------------------------------

import Text.ParserCombinators.Parsec -- Bibliothèque d'analyse syntaxique.
import Data.Char                -- Conversion de Chars de/vers Int et autres.
import System.IO                -- Pour stdout, hPutStr

---------------------------------------------------------------------------
-- 1ère représentation interne des expressions de notre language         --
---------------------------------------------------------------------------
data Sexp = Snil                        -- La liste vide
          | Scons Sexp Sexp             -- Une paire
          | Ssym String                 -- Un symbole
          | Snum Int                    -- Un entier
          -- Génère automatiquement un pretty-printer et une fonction de
          -- comparaison structurelle.
          deriving (Show, Eq)

-- Exemples:
-- (+ 2 3)  ==  (((() . +) . 2) . 3)
--          ==>  Scons (Scons (Scons Snil (Ssym "+"))
--                            (Snum 2))
--                     (Snum 3)
--                   
-- (/ (* (- 68 32) 5) 9)
--     ==  (((() . /) . (((() . *) . (((() . -) . 68) . 32)) . 5)) . 9)
--     ==>
-- Scons (Scons (Scons Snil (Ssym "/"))
--              (Scons (Scons (Scons Snil (Ssym "*"))
--                            (Scons (Scons (Scons Snil (Ssym "-"))
--                                          (Snum 68))
--                                   (Snum 32)))
--                     (Snum 5)))
--       (Snum 9)

---------------------------------------------------------------------------
-- Analyseur lexical                                                     --
---------------------------------------------------------------------------

pChar :: Char -> Parser ()
pChar c = do { _ <- char c; return () }

-- Les commentaires commencent par un point-virgule et se terminent
-- à la fin de la ligne.
pComment :: Parser ()
pComment = do { pChar ';'; _ <- many (satisfy (\c -> not (c == '\n')));
                (pChar '\n' <|> eof); return ()
              }
-- N'importe quelle combinaison d'espaces et de commentaires est considérée
-- comme du blanc.
pSpaces :: Parser ()
pSpaces = do { _ <- many (do { _ <- space ; return () } <|> pComment);
               return () }

-- Un nombre entier est composé de chiffres.
integer     :: Parser Int
integer = do c <- digit
             integer' (digitToInt c)
          <|> do _ <- satisfy (\c -> (c == '-'))
                 n <- integer
                 return (- n)
    where integer' :: Int -> Parser Int
          integer' n = do c <- digit
                          integer' (10 * n + (digitToInt c))
                       <|> return n

pSymchar :: Parser Char
pSymchar    = alphaNum <|> satisfy (\c -> c `elem` "!@$%^&*_+-=:|/?<>")
pSymbol :: Parser Sexp
pSymbol= do { s <- many1 (pSymchar);
              return (case parse integer "" s of
                        Right n -> Snum n
                        _ -> Ssym s)
            }

---------------------------------------------------------------------------
-- Analyseur syntaxique                                                  --
---------------------------------------------------------------------------

-- La notation "'E" est équivalente à "(shorthand-quote E)"
-- La notation "`E" est équivalente à "(shorthand-backquote E)"
-- La notation ",E" est équivalente à "(shorthand-comma E)"
pQuote :: Parser Sexp
pQuote = do { c <- satisfy (\c -> c `elem` "'`,"); pSpaces; e <- pSexp;
              return (Scons
                      (Scons Snil
                             (Ssym (case c of
                                     ',' -> "shorthand-comma"
                                     '`' -> "shorthand-backquote"
                                     _   -> "shorthand-quote")))
                      e) }

-- Une liste (Tsil) est de la forme ( [e .] {e} )
pTsil :: Parser Sexp
pTsil = do _ <- char '('
           pSpaces
           (do { _ <- char ')'; return Snil }
            <|> do hd <- (do e <- pSexp
                             pSpaces
                             (do _ <- char '.'
                                 pSpaces
                                 return e
                              <|> return (Scons Snil e)))
                   pLiat hd)
    where pLiat :: Sexp -> Parser Sexp
          pLiat hd = do _ <- char ')'
                        return hd
                 <|> do e <- pSexp
                        pSpaces
                        pLiat (Scons hd e)

-- Accepte n'importe quel caractère: utilisé en cas d'erreur.
pAny :: Parser (Maybe Char)
pAny = do { c <- anyChar ; return (Just c) } <|> return Nothing

-- Une Sexp peut-être une liste, un symbol ou un entier.
pSexpTop :: Parser Sexp
pSexpTop = do { pTsil <|> pQuote <|> pSymbol
                <|> do { x <- pAny;
                         case x of
                           Nothing -> pzero
                           Just c -> error ("Unexpected char '" ++ [c] ++ "'")
                       }
              }

-- On distingue l'analyse syntaxique d'une Sexp principale de celle d'une
-- sous-Sexp: si l'analyse d'une sous-Sexp échoue à EOF, c'est une erreur de
-- syntaxe alors que si l'analyse de la Sexp principale échoue cela peut être
-- tout à fait normal.
pSexp :: Parser Sexp
pSexp = pSexpTop <|> error "Unexpected end of stream"

-- Une séquence de Sexps.
pSexps :: Parser [Sexp]
pSexps = do pSpaces
            many (do e <- pSexpTop
                     pSpaces
                     return e)

-- Déclare que notre analyseur syntaxique peut-être utilisé pour la fonction
-- générique "read".
instance Read Sexp where
    readsPrec _ s = case parse pSexp "" s of
                      Left _ -> []
                      Right e -> [(e,"")]

---------------------------------------------------------------------------
-- Sexp Pretty Printer                                                   --
---------------------------------------------------------------------------

showSexp' :: Sexp -> ShowS
showSexp' Snil = showString "()"
showSexp' (Snum n) = showsPrec 0 n
showSexp' (Ssym s) = showString s
showSexp' (Scons e1 e2) = showHead (Scons e1 e2) . showString ")"
    where showHead (Scons Snil e') = showString "(" . showSexp' e'
          showHead (Scons e1' e2')
            = showHead e1' . showString " " . showSexp' e2'
          showHead e = showString "(" . showSexp' e . showString " ."

-- On peut utiliser notre pretty-printer pour la fonction générique "show"
-- (utilisée par la boucle interactive de GHCi).  Mais avant de faire cela,
-- il faut enlever le "deriving Show" dans la déclaration de Sexp.
{-
instance Show Sexp where
    showsPrec p = showSexp'
-}

-- Pour lire et imprimer des Sexp plus facilement dans la boucle interactive
-- de Hugs/GHCi:
readSexp :: String -> Sexp
readSexp = read
showSexp :: Sexp -> String
showSexp e = showSexp' e ""

---------------------------------------------------------------------------
-- Représentation intermédiaire "Lambda"                                 --
---------------------------------------------------------------------------

type Var = String

-- Type Haskell qui décrit les types Psil.
data Ltype = Lint
           | Larw Ltype Ltype   -- Type "arrow" des fonctions.
           deriving (Show, Eq)

-- Type Haskell qui décrit les expressions Psil.
data Lexp = Lnum Int            -- Constante entière.
          | Lvar Var            -- Référence à une variable.
          | Lhastype Lexp Ltype -- Annotation de type.
          | Lapp Lexp Lexp      -- Appel de fonction, avec un argument.
          | Llet Var Lexp Lexp  -- Déclaration de variable locale.
          | Lfun Var Lexp       -- Fonction anonyme.
          deriving (Show, Eq)

-- Type Haskell qui décrit les déclarations Psil.
data Ldec = Ldec Var Ltype      -- Déclaration globale.
          | Ldef Var Lexp       -- Définition globale.
          deriving (Show, Eq)
          

-- Conversion de Sexp à Lambda --------------------------------------------

s2t :: Sexp -> Ltype
s2t (Ssym "Int") = Lint
-- ¡¡COMPLÉTER ICI!!
s2t (Scons (Scons (Scons Snil (Ssym "Int")) (Ssym "->")) (Ssym "Int")) = Larw Lint Lint
--s2t (Scons (Scons (Scons Snil t1) (Ssym "->")) t2) = Larw (s2t t1) (s2t t2)

s2t sexpr = 
  let 
    liste = s2listS sexpr
  in 
    ls2t liste
  
s2t se = error ("Type Psil inconnu: " ++ (showSexp se))

------------------------------------------------------
-- fonction qui prend la liste de Sexp et transforme en arrow

ls2t :: [Sexp] -> Ltype
ls2t list@(x:xs) =
  case list of
     [t1, (Ssym "->"), t2 ] -> Larw (s2t t1) (s2t t2)
     _ -> Larw (s2t x) (ls2t xs) 

-------------------------------------------------------
-- fonction qui prend un Sexp et renvoie une liste de ses Sexp. 
-- Par exemple, sur (Scons (Scons (Scons Snil t1) (Ssym "->")) t2), 
-- elle renverrait [t1, Ssym "->", t2]. 
s2listS :: Sexp -> [Sexp]
s2listS (Scons Snil t1) = [t1]
s2listS  (Scons e1 t2) = (s2listS e1) ++ [t2] -- pas efficace, changer apres 
-----------------------------------------------------     

{-
s2t (Scons Snil e) = s2t e 
--s2t (Scons (Scons (Scons Snil e1) (Ssym "->")) e2) = Larw (s2t e1) (s2t e2)
s2t (Scons e (Ssym "->")) = s2t e
s2t (Scons e1 e2) = Larw (s2t e1) (s2t e2) 
-}
--s2t (Scons (Scons (Scons Snil (Ssym "Int")) (Ssym "Int"))(Ssym "->")) = Larw Lint Lint
--s2t (Scons e (Ssym "Int") ) = Larw Lint (s2t e)




-- "elabore" une expression de type Sexp en Lexp
s2l :: Sexp -> Lexp
s2l (Snum n) = Lnum n
s2l (Ssym s) = Lvar s
-- ¡¡COMPLÉTER ICI!!

-- Lexp pour appels en psil du genre: "(e)"
s2l (Scons Snil e) = s2l e

-- Lexp pour déclarations de type en psil: "(: e τ)"
s2l (Scons (Scons (Scons Snil (Ssym ":")) e) t) = Lhastype (s2l e) (s2t t)

-- Lexp pour fonctions en psil: "(fun x e)"
s2l (Scons (Scons (Scons Snil (Ssym "fun")) (Ssym x)) e) = Lfun x (s2l e)

-- Lexp pour let en psil: "(let ((x e1)) e2)"
s2l (Scons (Scons (Scons Snil (Ssym "let"))
  (Scons Snil (Scons (Scons Snil (Ssym x)) e1))) e2)
    = Llet x (s2l e1) (s2l e2)

-- Lexp pour appels de fonctions en psil: "(fct arg)"
s2l (Scons fct arg) = Lapp (s2l fct) (s2l arg)

-- 
s2d :: Sexp -> Ldec
s2d (Scons (Scons (Scons Snil (Ssym "def")) (Ssym v)) e) = Ldef v (s2l e)

--s2d (Scons (Scons (Scons Snil (Ssym "def")) (Ssym v)) e) =
--    trace (show e) $ Ldef v (s2l e)

-- ¡¡COMPLÉTER ICI!!

s2d (Scons (Scons (Scons Snil (Ssym "dec")) (Ssym v)) e) = Ldec v (s2t e)
--s2d (Scons (Scons (Scons Snil (Ssym "dec")) (Ssym v)) e) = 
--  trace (show e) $ Ldec v (s2t e)


s2d se = error ("Déclaration Psil inconnue: " ++ showSexp se)

---------------------------------------------------------------------------
-- Vérification des types                                                --
---------------------------------------------------------------------------

-- Type des tables indexées par des `α` qui contiennent des `β`.
-- Il y a de bien meilleurs choix qu'une liste de paires, mais
-- ça suffit pour notre prototype.
type Map α β = [(α, β)]

-- Transforme une `Map` en une fonctions (qui est aussi une sorte de "Map").
mlookup :: Map Var β -> (Var -> β)
mlookup [] x = error ("Uknown variable: " ++ show x)
mlookup ((x,v) : xs) x' = if x == x' then v else mlookup xs x'

minsert :: Map Var β -> Var -> β -> Map Var β
minsert m x v = (x,v) : m

type TEnv = Map Var Ltype
type TypeError = String

-- L'environment de typage initial.
tenv0 :: TEnv
tenv0 = [("+", Larw Lint (Larw Lint Lint)),
         ("-", Larw Lint (Larw Lint Lint)),
         ("*", Larw Lint (Larw Lint Lint)),
         ("/", Larw Lint (Larw Lint Lint)),
         ("if0", Larw Lint (Larw Lint (Larw Lint Lint)))]

-- `check Γ e τ` vérifie que `e` a type `τ` dans le contexte `Γ`.
check :: TEnv -> Lexp -> Ltype -> Maybe TypeError
-- ¡¡COMPLÉTER ICI!!
---------------
{-Lfun Var Lexp -}
-- Déclaration fonction anonyme
-- Pour vérifier que la fonction a bien le type (t1 -> t2)
-- 1º checker que expr a le type t2 dans l'env auquel on ajoute (x,t1)
-- 2º reenvoier Maybe TypeError
check tenv (Lfun x expr) (Larw t1 t2) = check ((x,t1):tenv) expr t2
---------------

check tenv e t
  -- Essaie d'inférer le type et vérifie alors s'il correspond au
  -- type attendu.
  = let t' = synth tenv e
    in if t == t' then Nothing
       else Just ("Erreur de type: " ++ show t ++ " ≠ " ++ show t')

-- `synth Γ e` vérifie que `e` est typé correctement et ensuite "synthétise"
-- et renvoie son type `τ`.
synth :: TEnv -> Lexp -> Ltype
synth _    (Lnum _) = Lint
synth tenv (Lvar v) = mlookup tenv v
synth tenv (Lhastype e t) =
    case check tenv e t of
      Nothing -> t
      Just err -> error err
-- ¡¡COMPLÉTER ICI!!
-- Appel de fonction, avec un argument
-- 1º "synthétiser" le type (t1 -> t2) en analysant e1
-- 2º checker que e2 a le type t1
-- 3º reenvoier t2
synth tenv (Lapp e1 e2) = 
    case synth tenv e1 of
      Larw t1 t2 -> case check tenv e2 t1 of
                      Nothing -> t2
                      Just err -> error err
      _ -> error ((show e1) ++ " n'est pas une fonction")

{-Llet Var Lexp Lexp  -- Déclaration de variable locale. -}
-- 1º "synthétiser" le type t1 en analysant e1
-- 2º "synthétiser" le type t2 en analysant e2 dans l'env auquel on a ajouté (x,t1)
-- 3º reenvoier t2
synth tenv (Llet x e1 e2) =
  let
    t1 = synth tenv e1 
    t2 = synth ((x,t1):tenv) e2 
  in 
    t2

synth _tenv e = error ("Incapable de trouver le type de: " ++ (show e))

---------------------------------------------------------------------------
-- Évaluateur                                                            --
---------------------------------------------------------------------------

-- Type des valeurs renvoyées par l'évaluateur.
data Value = Vnum Int
           | Vfun VEnv Var Lexp
           | Vop (Value -> Value) -- Vprim (Val → Val) -- Une primitive ?

type VEnv = Map Var Value

instance Show Value where
    showsPrec p  (Vnum n) = showsPrec p n
    showsPrec _p (Vfun _ _ _) = showString "<fermeture>"
    showsPrec _p (Vop _) = showString "<fonction>"

-- L'environnement initial qui contient les fonctions prédéfinies.
venv0 :: VEnv
venv0 = [("+", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x + y)))),
         ("-", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x - y)))),
         ("*", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x * y)))),
         ("/", Vop (\ (Vnum x) -> Vop (\ (Vnum y) -> Vnum (x `div` y)))),
         ("if0", Vop (\ (Vnum x) ->
                       case x of
                         0 -> Vop (\ v1 -> Vop (\ _ -> v1))
                         _ -> Vop (\ _ -> Vop (\ v2 -> v2))))]

-- La fonction d'évaluation principale.
eval :: VEnv -> Lexp -> Value
eval _venv (Lnum n) = Vnum n
eval venv (Lvar x) = mlookup venv x
-- ¡¡COMPLÉTER ICI!!
eval venv (Lhastype expr t) =  
  eval venv expr
-- je pense qu'il faut verifier le type ici, car process_decl n'évalue pas, 
--voir si il y a une autre partie qui evalue

-- eval venv (Lapp fun arg) = -- fonction indsirée de la démo #4.1
--   let
--     valFun = eval venv fun
--     valArg = eval venv arg
--   in
--     case valFun of
--       Vnum _ -> error "n'est pas une fonction"
--       Vop f -> f valArg
--       _ -> error "faire le cas Vfun error inconu?"
--       --Vfun f -> f valArg

eval venv (Lapp fun actual) =
  case (eval venv fun) of
    Vfun funEnv formal body -> eval ((formal,(eval venv actual)) : funEnv) body
    Vnum _ -> error "n'est pas une fonction"
    Vop f -> f (eval venv actual)
-- eval env (Elambda arg body) =
--         Vfun env arg body
-- eval env (Ecall fun actual) =
--         case (eval env fun) of
--             Vfun funEnv formal body -> eval ((formal, actual) : funEnv) body


eval venv (Llet varName varExp expr) =
  let
    --venv' = (varName, eval venv varExp) : venv -- appel par valeur?
    venv' = minsert venv varName (eval venv varExp)
  in
    eval venv' expr

-- data Value = Vnum Int
--            | Vfun VEnv Var Lexp
--            | Vop (Value -> Value) -- Vprim (Val → Val) -- Une primitive ?

-- je pense que si expr est une fonction il faut envoyer Vfun 
-- eval venv (Lfun var (Lnum n)) = Vnum n 
-- eval venv (Lfun var (Lvar x)) = mlookup venv x
--eval venv (Lfun var expr) = Vfun venv var (eval venv exp)
eval venv (Lfun var exp@(Lfun var2 exp2)) = Vfun venv var exp 
eval venv (Lfun var expr) = Vfun venv var expr

--eval venv (Lfun var exp) = Vop (\ (Vnum var) -> eval venv exp) -- expression bien typée, mais est-ce que ça fonctionne?

-- État de l'évaluateur.
type EState = ((TEnv, VEnv),       -- Contextes de typage et d'évaluation.
               Maybe (Var, Ltype), -- Déclaration en attente d'une définition.
               [(Value, Ltype)])   -- Résultats passés (en ordre inverse).

-- Évalue une déclaration, y compris vérification des types.
process_decl :: EState -> Ldec -> EState
process_decl (env, Nothing, res) (Ldec x t) = (env, Just (x,t), res)

process_decl (env, Just (x', _), res) (decl@(Ldec _ _)) =
    process_decl (env, Nothing,
                  error ("Manque une définition pour: " ++ x') : res)
                 decl

process_decl ((tenv, venv), Nothing, res) (Ldef x e) =
    -- Le programmeur n'a *pas* fourni d'annotation de type pour `x`.
    let ltype = synth tenv e
        tenv' = minsert tenv x ltype
        val = eval venv e
        venv' = minsert venv x val
    in ((tenv', venv'), Nothing, (val, ltype) : res)
-- ¡¡COMPLÉTER ICI!!

process_decl ((tenv, venv), Just (v,t) , res) (Ldef x e) =
  if check tenv e t == Nothing then    -- si le type de la définition correspond au type de la déclaration
    let
      val = eval venv e
      venv' = minsert venv x val
      tenv' = minsert tenv x t -- inserer, evaluer seulement si le meme

    in
      ((tenv', venv'), Nothing, (val, t) : res) -- ajouter à l'environnement
  else
    error "Défintion avec un type ne correspondant pas à la déclaration."

--test5 = process_decl ((tenv, venv), Just (v,t) , res) (Ldef x e) 

{-
process_decl ((tenv, venv), Just (v,t) , res) (Ldef x e) =
    -- Le programmeur a *fourni* d'annotation ou a declaré de type pour `x`.
    -- ne pas utiliser synth pour Lfun, utiliser plutot
    -- utiliser check
    if check v t then 
      let ltype = t--synth tenv e
        tenv' = minsert tenv x ltype -- inserer, evaluer seulement si le meme
        val = eval venv e
        venv' = minsert venv x val
      in 
        if t == ltype then
          ((tenv', venv'), Nothing, (val, ltype) : res)
        else
          error ("variable déja declaré avec un autre type")
-}
---------------------------------------------------------------------------
-- Toplevel                                                              --
---------------------------------------------------------------------------

process_sexps :: EState -> [Sexp] -> IO ()
process_sexps _ [] = return ()
process_sexps es (sexp : sexps) =
    let decl = s2d sexp
        (env', pending, res) = process_decl es decl
    in do (hPutStr stdout)
            (concat
             (map (\ (val, ltyp) ->
                   "  " ++ show val ++ " : " ++ show ltyp ++ "\n")
              (reverse res)))
          process_sexps (env', pending, []) sexps

-- Lit un fichier contenant plusieurs Sexps, les évalue l'une après
-- l'autre, et renvoie la liste des valeurs obtenues.
run :: FilePath -> IO ()
run filename
  = do filestring <- readFile filename
       let sexps = case parse pSexps filename filestring of
                     Left err -> error ("Parse error: " ++ show err)
                     Right es -> es
       process_sexps ((tenv0, venv0), Nothing, []) sexps

sexpOf :: String -> Sexp
sexpOf = read

-- lexOf : transforme la commende en en Lexpression
lexpOf :: String -> Lexp
lexpOf = s2l . sexpOf

typeOf :: String -> Ltype
typeOf = synth tenv0 . lexpOf

-- evalue lexpression et transforme en Value
valOf :: String -> Value
valOf = eval venv0 . lexpOf
