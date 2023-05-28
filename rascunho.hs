-- a efacer apres : teste
--s2l (Scons (Scons Snil (Ssym "+")) (Snum 2)) = Lapp (Lvar "+") (Lnum 2)

{-
synth tenv (Lapp e1 e2) = 
    case synth tenv e1 of
       Larw t1 t2 -> if( check tenv e2 t1 == Nothing) then t2 else error "type "
       otherwise -> error ""
-}