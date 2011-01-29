#!/usr/bin/env runhaskell


-- ---------------------------------------------------------------------------
--  Intel Concurrent Collections for Haskell
--  Copyright (c) 2010, Intel Corporation.
-- 
--  This program is free software; you can redistribute it and/or modify it
--  under the terms and conditions of the GNU Lesser General Public License,
--  version 2.1, as published by the Free Software Foundation.
-- 
--  This program is distributed in the hope it will be useful, but WITHOUT
--  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
--  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public License for
--  more details.
-- 
--  You should have received a copy of the GNU Lesser General Public License along with
--  this program; if not, write to the Free Software Foundation, Inc., 
--  51 Franklin St - Fifth Floor, Boston, MA 02110-1301 USA.
-- ---------------------------------------------------------------------------


-- This is a script used for timing the throughput of benchmarks that
-- take one argument and have linear complexity.


module Benchmark.BinSearch 
    (
      binSearch
    )
where

import Control.Monad
import Data.Time.Clock -- Not in 6.10
import Data.List
import Data.IORef
import System
import System.IO
import System.Cmd
import System.Exit
import Debug.Trace

-- In seconds:
--desired_exec_length = 3



-- | Binary search for the number of inputs to a computation that
-- | makes it take a specified time in seconds.
--
-- > binSearch verbose N (min,max) kernel
--
-- | binSearch will find the right input size that results in a time
-- | between min and max, then it will then run for N trials and
-- | return the median (input,time-in-seconds) pair.
binSearch :: Bool -> Integer -> (Double,Double) -> (Integer -> IO ()) -> IO (Integer, Double)
binSearch verbose trials (min,max) kernel =
  do 
     when(verbose)$ putStrLn$ "[binsearch] Binary search for input size resulting in time in range "++ show (min,max)

     let desired_exec_length = 1.0
	 good_trial t = (toRational t <= toRational max) && (toRational t >= toRational min)

	 --loop :: Bool -> [String] -> Int -> Integer -> IO ()

	 -- At some point we must give up...
	 loop n | n > (2 ^ 100) = error "ERROR binSearch: This function doesn't seem to scale in proportion to its last argument."

	 -- Not allowed to have "0" size input, bump it back to one:
	 loop 0 = loop 1

	 loop n = 
	    do 
	       when(verbose)$ putStr$ "[binsearch:"++ show n ++ "] "
	       -- hFlush stdout

	       time <- timeit$ kernel n

	       when(verbose)$ putStrLn$ "Time consumed: "++ show time
	       -- hFlush stdout
	       let rate = fromIntegral n / time

	       -- [2010.06.09] Introducing a small fudge factor to help our guess get over the line: 
	       let initial_fudge_factor = 1.10
		   fudge_factor = 1.01 -- Even in the steady state we fudge a little
		   guess = desired_exec_length * rate 

   -- TODO: We should keep more history here so that we don't re-explore input space we have already explored.
   --       This is a balancing act because of randomness in execution time.

	       if good_trial time
		then do 
			when(verbose)$ putStrLn$ "[binsearch] Time in range.  LOCKING input size and performing remaining trials."
			print_trial 1 n time
			lockin (trials-1) n [time]

		-- Here we're still in the doubling phase:
		else if time < 0.100 
		then loop (2*n)

		else do when(verbose)$ putStrLn$ "[binsearch] Estimated rate to be "++show (round$ rate)++" per second.  Trying to scale up..."

			-- Here we've exited the doubling phase, but we're making our first guess as to how big a real execution should be:
			if time > 0.100 && time < 0.33 * desired_exec_length
			   then do when(verbose)$ putStrLn$  "[binsearch]   (Fudging first guess a little bit extra)"
				   loop (round$ guess * initial_fudge_factor)
			   else    loop (round$ guess * fudge_factor)

 	 -- Termination condition: Done with all trials.
         lockin 0 n log = do when(verbose)$ putStrLn$ "[binsearch] Time-per-unit for all trials: "++ 
				            (concat $ intersperse " " (map (show . (/ toDouble n) . toDouble) $ sort log))
			     return (n, log !! ((length log) `quot` 2)) -- Take the median

         lockin trials_left n log = 
		     do when(verbose)$ putStrLn$ "[binsearch]------------------------------------------------------------"
			time <- timeit$ kernel n
			-- hFlush stdout
			print_trial (trials - trials_left +1 ) n time
			-- when(verbose)$ hFlush stdout
			lockin (trials_left - 1) n (time : log)

         print_trial trialnum n time = 
	     let rate = fromIntegral n / time
	         timeperunit = time / fromIntegral n
	     in
			when(verbose)$ putStrLn$ "[binsearch]  TRIAL: "++show trialnum ++
				                 " secPerUnit: "++ showTime timeperunit ++ 
						 " ratePerSec: "++ show (rate) ++ 
						 " seconds: "++showTime time



     (n,t) <- loop 1
     return (n, fromRational$ toRational t)

showTime t = show ((fromRational $ toRational t) :: Double)
toDouble :: Real a => a -> Double
toDouble = fromRational . toRational


-- Could use cycle counters here.... but the point of this is to time
-- things on the order of a second.
timeit io = 
    do strt <- getCurrentTime
       io       
       end  <- getCurrentTime
       return (diffUTCTime end strt)

test = 
  binSearch True 3 (1.0, 1.05)
   (\n -> 
    do v <- newIORef 0
       forM_ [1..n] $ \i -> do
         old <- readIORef v
         writeIORef v (old+i))
