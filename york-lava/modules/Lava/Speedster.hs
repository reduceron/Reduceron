module Lava.Speedster
  ( writeSpeedsterVhdl
  ) where

import Lava.Bit
import Lava.Binary
import System

vhdlGumpth :: String
vhdlGumpth = unlines $
  [ "-- Generated by York Lava for Synplify / Achronix ACE"
  , ""
  , "library IEEE;"
  , "use IEEE.STD_LOGIC_1164.ALL;"
  , "use IEEE.STD_LOGIC_ARITH.ALL;"
  , "use IEEE.STD_LOGIC_UNSIGNED.ALL;"
  , ""
  , "library unisim;"
  , "use unisim.vcomponents.all;"
  , ""
  , "use work.all;"
  , ""
  ]

vhdlEntity :: String -> Netlist -> String
vhdlEntity name nl =
     "entity " ++ name ++ " is port (\n"
  ++ consperse ";\n"
       ([ v ++ " : out std_logic" | v <- outs]  ++
        [ "clock : in  std_logic"            ]  ++
        [ v ++ " : in  std_logic" | v <- inps])
  ++ "\n);\nend entity " ++ name ++ ";\n"
  where
    inps = [ lookupParam (netParams net) "name"
           | net <- nets nl, netName net == "name"]
    outs = map fst (namedOutputs nl)

ramFile :: Part -> String -> String -> [Parameter] -> String
ramFile part name ramType params = unlines commands
  where
    init = read (lookupParam params "init") :: [Integer]
    dwidth = read (lookupParam params "dwidth") :: Int
    awidth = read (lookupParam params "awidth") :: Int
    primType = lookupParam params "primtype"

    coeFile = if null init then "no_coe_file_loaded"
                           else "init_" ++ name ++ ".txt"

    commands =
      [ "SET addpads = False"
      , "SET asysymbol = True"
      , "SET busformat = BusFormatAngleBracketNotRipped"
      , "SET createndf = False"
      , "SET designentry = VHDL"
      , "SET device = " ++ partName part
      , "SET devicefamily = " ++ partFamily part
      , "SET package = " ++ partPackage part
      , "SET speedgrade = " ++ partSpeedGrade part
      , "SET flowvendor = Foundation_iSE"
      , "SET formalverification = False"
      , "SET foundationsym = False"
      , "SET implementationfiletype = Ngc"
      , "SET removerpms = False"
      , "SET simulationfiles = Behavioral"
      , "SET verilogsim = False"
      , "SET vhdlsim = True"
      , "# END Project Options"
      , "# BEGIN Select"
      , "SELECT Block_Memory_Generator family Xilinx,_Inc. 2.8"
      , "# END Select"
      , "# BEGIN Parameters"
      , if null primType then "CSET algorithm=Minimum_Area"
                         else "CSET algorithm=Fixed_Primitives"
      --, "CSET assume_synchronous_clk=true"
      , "CSET assume_synchronous_clk=false"
      , "CSET byte_size=9"
      , "CSET coe_file=" ++ coeFile
      , "CSET collision_warnings=ALL"
      , "CSET component_name=" ++ name
      , "CSET disable_collision_warnings=false"
      , "CSET disable_out_of_range_warnings=false"
      , "CSET ecc=false"
      , "CSET enable_a=Always_Enabled"
      , "CSET enable_b=Always_Enabled"
      , "CSET fill_remaining_memory_locations=true"
      , "CSET load_init_file=" ++
          (if coeFile == "no_coe_file_loaded" then "false" else "true")
      , "CSET memory_type=" ++
          (if ramType == "ram" then "Single_Port_RAM"
                               else "True_Dual_Port_RAM")
      , "CSET operating_mode_a=WRITE_FIRST"
      , "CSET operating_mode_b=WRITE_FIRST"
      , "CSET output_reset_value_a=0"
      , "CSET output_reset_value_b=0"
      , "CSET pipeline_stages=0"
      , "CSET primitive=" ++ if null primType then "8kx2" else primType
      , "CSET read_width_a=" ++ show dwidth
      , "CSET read_width_b=" ++ show dwidth
      , "CSET register_porta_output_of_memory_core=false"
      , "CSET register_porta_output_of_memory_primitives=false"
      , "CSET register_portb_output_of_memory_core=false"
      , "CSET register_portb_output_of_memory_primitives=false"
      , "CSET remaining_memory_locations=0"
      , "CSET single_bit_ecc=false"
      , "CSET use_byte_write_enable=false"
      , "CSET use_ramb16bwer_reset_behavior=false"
      , "CSET use_regcea_pin=false"
      , "CSET use_regceb_pin=false"
      , "CSET use_ssra_pin=false"
      , "CSET use_ssrb_pin=false"
      , "CSET write_depth_a=" ++ show (2^awidth)
      , "CSET write_width_a=" ++ show dwidth
      , "CSET write_width_b=" ++ show dwidth
      , "# END Parameters"
      , "GENERATE"
      ]

vhdlDecls :: Netlist -> String
vhdlDecls nl =
     (consperse ",\n"
        [ consperse ",\n" $ map (wireStr . (,) (netId net))
                                [0..netNumOuts net-1]
        | net <- nets nl ])
  ++ " : std_logic;\n"
  ++ "attribute INIT: string;\n"
  ++ concat [ init (netId net) (netParams net)
            | net <- nets nl
            , netName net == "delay" || netName net == "delayEn" ]
  where
    init c params =
         "attribute INIT of " ++ compStr c ++ ": label is \""
      ++ lookupParam params "init" ++ "\";\n"

type Instantiator = String -> [Parameter] -> InstanceId -> [Wire] -> String

vhdlInsts :: Instantiator -> Netlist -> String
vhdlInsts f nl =
  concat [ f (netName net)
             (netParams net)
             (netId net)
             (netInputs net)
         | net <- nets nl ] ++
  concat [ s ++ " <= " ++ wireStr w ++ ";\n"
         | (s, w) <- namedOutputs nl ]

vhdlInst :: Instantiator
vhdlInst "low"     = constant "'0'"
vhdlInst "high"    = constant "'1'"
vhdlInst "inv"     = uniop "not"
vhdlInst "and2"    = binop "and"
vhdlInst "or2"     = binop "or"
vhdlInst "xor2"    = binop "xor"
vhdlInst "eq2"     = binop "xnor"
vhdlInst "xorcy"   = \params comp [ci,li] ->
                       gate 1 "xorc" params comps [li,ci]
vhdlInst "muxcy"   = \params comp [ci,di,s] ->
                       gate 1 "muxc" params comps [s,di,ci]
vhdlInst "name"    = assignName
vhdlInst "delay"   = delay "dff"
vhdlInst "delayEn" = \params comp [ce, d] ->
                       delay "dffe" params comp [d, ce]
vhdlInst "ram"     = instRam
vhdlInst "dualRam" = instRam2
vhdlInst s = error ("Vhdl: unknown component '" ++ s ++ "'")

vhdlArch :: Instantiator -> String -> Netlist -> String
vhdlArch f name nl =
     "architecture structural of " ++ name ++ " is\n"
  ++ "signal " ++ vhdlDecls nl
  ++ "begin\n"
  ++ vhdlInsts f nl
  ++ "end structural;\n"

ramFiles :: Part -> Netlist -> [(String, String)]
ramFiles part nl =
    [ ( "init_ram_" ++ compStr (netId net) ++ ".txt"
      , genCoeFile $ netParams net)
    | net <- nets nl
    , netName net == "ram" || netName net == "dualRam"
    , nonEmpty (netParams net)
    ]
 ++ [ ( "ram_" ++ compStr (netId net) ++ ".xco"
      , ramFile part
                ("ram_" ++ compStr (netId net))
                (netName net)
                (netParams net))
    | net <- nets nl
    , netName net == "ram" || netName net == "dualRam"
    ]
  where
    nonEmpty params = not (null init)
      where init = read (lookupParam params "init") :: [Integer]

    genCoeFile params =
         "memory_initialization_radix = 10;\n"
      ++ "memory_initialization_vector = "
      ++ (unwords $ map show init)
      ++ ";\n"
     where init = read (lookupParam params "init") :: [Integer]

vhdl :: Part -> String -> Netlist -> [(String, String)]
vhdl part name nl =
  [ (name ++ ".vhd", vhdlGumpth
                  ++ vhdlEntity name nl
                  ++ vhdlArch vhdlInst name nl) ] ++ ramFiles part nl

{-|

For example, the function

> halfAdd :: Bit -> Bit -> (Bit, Bit)
> halfAdd a b = (sum, carry)
>   where
>     sum   = a <#> b
>     carry = a <&> b

can be converted to a VHDL entity with inputs named @a@ and @b@ and
outputs named @sum@ and @carry@.

> synthesiseHalfAdd :: IO ()
> synthesiseHalfAdd =
>   writeVhdl "HalfAdd"
>             (halfAdd (name "a") (name "b"))
>             (name "sum", name "carry")

The function 'writeVhdl' assumes that the part (FPGA chip) you are
targetting is the @Virtex-5-110t-ff1136-1@, because that is what sits
at my desk.  This is /only/ important if your design contains RAMs.
If your design does contain RAMs, and you wish to target a different
part, then use the 'writeVhdlForPart' function.  Xilinx's fault!

-}
writeVhdl ::
  Generic a => String -- ^ The name of VHDL entity, which is also the
                      -- name of the directory that the output files
                      -- are written to.
            -> a      -- ^ The Bit-structure that is turned into VHDL.
            -> a      -- ^ Names for the outputs of the circuit.
            -> IO ()
writeVhdl = writeVhdlForPart v5110t

-- | Like 'writeVhdl', but allows the target part (FPGA chip) to be specified.
writeVhdlForPart ::
  Generic a => Part   -- ^ Part (FPGA chip) being targetted.
            -> String -- ^ The name of VHDL entity, which is also the
                      -- name of the directory that the output files
                      -- are written to.
            -> a      -- ^ The Bit-structure that is turned into VHDL.
            -> a      -- ^ Names for the outputs of the circuit.
            -> IO ()
writeVhdlForPart part name a b =
  do putStrLn ("Creating directory '" ++ name ++ "/'")
     system ("mkdir -p " ++ name)
     nl <- netlist a b
     mapM_ gen (vhdl part name nl)
     putStrLn "Done."
  where
    gen (file, content) =
      do putStrLn $ "Writing to '" ++ name ++ "/" ++ file ++ "'"
         writeFile (name ++ "/" ++ file) content

-- Auxiliary functions

compStr :: InstanceId -> String
compStr i = "c" ++ show i

wireStr :: Wire -> String
wireStr (i, j) = "w" ++ show i ++ "_" ++ show j

consperse :: String -> [String] -> String
consperse s [] = ""
consperse s [x] = x
consperse s (x:y:ys) = x ++ s ++ consperse s (y:ys)

argList :: [String] -> String
argList = consperse ","

uniop str params comp [a] =
  wireStr (comp, 0) ++ " <== " ++ str ++ " " ++ wireStr a ++ ";\n"

binop str params comp [a,b] =
  wireStr (comp, 0) ++ " <== " ++ wireStr a ++ " " ++ str ++ " "
                               ++ wireStr b ++ ";\n"

gate n str params comp inps =
  compStr comp ++ " : " ++ str ++ " port map (" ++ argList (xs ++ ys) ++ ");\n"
  where xs = map (\i -> wireStr (comp, i)) [0..n-1]
        ys = map wireStr inps

assignName params comp inps =
  wireStr (comp, 0)  ++ " <= " ++ lookupParam params "name" ++ ";\n"

muxBit params comp [b, a, sel] =
  "with " ++ wireStr sel ++ " select "
          ++ wireStr (comp, 0)  ++ " <= " ++ wireStr a ++ " when '0',"
                                ++ wireStr b ++ " when '1';\n"

constant str params comp inps =
  wireStr (comp, 0) ++ " <= " ++ str ++ ";\n"

delay str params comp inps =
  compStr comp ++ " : " ++ str
  --             ++ " generic map (INIT => '"
  --             ++ lookupParam params "init" ++ "') "
               ++ "port map ("
               ++ argList ( (wireStr (comp, 0):map wireStr (tail inps))
                                 ++ "clock")
               ++ ");\n"

-- Block ram synthesis for Virtex 5 using Xilinx core-generator

busMap :: String -> [Wire] -> [String]
busMap port signals =
  zipWith (\i s -> port ++ "(" ++ show i ++ ") => " ++ wireStr s) [0..] signals

instRam params comp (we:sigs) =
    compStr comp ++ " : entity ram_" ++ compStr comp ++ " "
                 ++ " port map ("
                 ++ " clka => clock, "
                 ++ argList (busMap "dina" dbus1) ++ ","
                 ++ argList (busMap "addra" abus1) ++ ","
                 ++ " wea(0) => " ++ wireStr we ++ ","
                 ++ argList (busMap "douta" outs1)
                 ++ ");\n"
  where
    init = read (lookupParam params "init") :: [Integer]
    dwidth = read (lookupParam params "dwidth") :: Int
    awidth = read (lookupParam params "awidth") :: Int
    primType = lookupParam params "primtype"

    (dbus1, abus1) = splitAt dwidth sigs
    outs1          = map ((,) comp) [0..dwidth-1]

instRam2 params comp (we1:we2:sigs) =
    compStr comp ++ " : entity ram_" ++ compStr comp ++ " "
                 ++ " port map ("
                 ++ " clka => clock, "
                 ++ argList (busMap "dina" dbus1) ++ ","
                 ++ argList (busMap "addra" abus1) ++ ","
                 ++ " wea(0) => " ++ wireStr we1 ++ ","
                 ++ argList (busMap "douta" outs1) ++ ","
                 ++ " clkb => clock, "
                 ++ argList (busMap "dinb" dbus2) ++ ","
                 ++ argList (busMap "addrb" abus2) ++ ","
                 ++ " web(0) => " ++ wireStr we2 ++ ","
                 ++ argList (busMap "doutb" outs2)
                 ++ ");\n"
  where
    init = read (lookupParam params "init") :: [Integer]
    dwidth = read (lookupParam params "dwidth") :: Int
    awidth = read (lookupParam params "awidth") :: Int
    primType = lookupParam params "primtype"

    (dbus, abus)   = splitAt (2*dwidth) sigs
    (abus1, abus2) = splitAt awidth abus
    (dbus1, dbus2) = splitAt dwidth dbus
    outs1          = map ((,) comp) [0..dwidth-1]
    outs2          = map ((,) comp) [dwidth..dwidth*2-1]
