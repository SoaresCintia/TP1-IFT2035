e1 = (Scons (Scons (Scons Snil (Ssym "Int")) (Ssym "->")) (Ssym "Int"))
e2 = (Scons (Scons (Scons (Scons Snil (Ssym "Int")) (Ssym "Int")) (Ssym "->")) (Ssym "Int"))
e3 = (Scons (Scons (Scons (Scons (Scons Snil (Ssym "Int")) (Ssym "Int")) (Ssym "Int")) (Ssym "->")) (Ssym "Int"))

--ghci> sexpOf "(Int (Int -> Int) -> Int)"
e4 = Scons (Scons (Scons (Scons Snil (Ssym "Int")) 
                         (Scons (Scons (Scons Snil (Ssym "Int")) 
                                       (Ssym "->")) 
                                (Ssym "Int"))) 
                  (Ssym "->")) 
            (Ssym "Int")


list1 = [Ssym "Int",Ssym "->",Ssym "Int"]
testL1 = trace (show list1) $ ls2t list1


list2 = [Ssym "Int",Ssym "Int",Ssym "->",Ssym "Int"]
testL2 = trace (show list2) $ ls2t list2


list3 = [Ssym "Int",Ssym "Int",Ssym "Int",Ssym "->",Ssym "Int"]
testL3 = trace (show list3) $ ls2t list3

list4 = test4
testL4 = trace (show list4) $ ls2t list4

------------------------------------------------------




test = trace (show e) $ s2listS e
test2 = trace (show e2) $ s2listS e2
test3 =  trace (show e3) $ s2listS e3

test4 = trace (show e4) $ s2listS e4