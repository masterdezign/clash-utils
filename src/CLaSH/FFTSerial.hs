{-| Radix 2 complex-to-complex Cooley-Tukey FFTs. https://en.wikipedia.org/wiki/Cooley%E2%80%93Tukey_FFT_algorithm.
    The FFTs in this module are serial, saving multiplers and routing resources. They operate on and produce two complex numbers at a time. 
-}
module CLaSH.FFTSerial (
    fftSerialStep,
    fftSerial
    ) where

import CLaSH.Prelude

import CLaSH.Complex
import CLaSH.FFT(halveTwiddles)

--Decimation in time
--2^(n + 1) == size of FFT / 2 == number of butterfly input pairs
-- | A step in the serial FFT decimation in time algorithm. Consumes and produces two complex samples per cycle. 
fftSerialStep
    :: forall n a. (KnownNat n, Num a)
    => Vec (2 ^ (n + 1)) (Complex a) -- ^ Precomputed twiddle factors
    -> Signal Bool                   -- ^ Input enable signal
    -> Signal (Complex a, Complex a) -- ^ Pair of input samples
    -> Signal (Complex a, Complex a) -- ^ Pair of output samples
fftSerialStep twiddles en input = bundle (butterflyHighOutput, butterflyLowOutput)
    where

    counter :: Signal (BitVector (n + 1))
    counter = regEn 0 en (counter + 1)

    (stage' :: Signal (BitVector 1), address' :: Signal (BitVector n)) = unbundle $ split <$> counter

    stage :: Signal Bool
    stage = unpack <$> stage'

    address :: Signal (Unsigned n)
    address = unpack <$> address'

    upperData = mux (not <$> regEn False en stage) (regEn 0 en $ fst <$> input) lowerRamReadResult

    lowerData = mux (not <$> regEn False en stage) lowerRamReadResult (regEn 0 en $ fst <$> input)

    lowerRamReadResult = blockRamPow2 (repeat 0 :: Vec (2 ^ n) (Complex a)) address 
        $ mux en (Just <$> bundle (address, snd <$> input)) (pure Nothing)

    upperRamReadResult = blockRamPow2 (repeat 0 :: Vec (2 ^ n) (Complex a)) (regEn 0 en address)
        $ mux en (Just <$> bundle (regEn 0 en address, upperData)) (pure Nothing)

    --Finally, the butterfly
    butterflyHighInput = upperRamReadResult
    butterflyLowInput  = regEn 0 en lowerData

    twiddle  = (twiddles !!) <$> (regEn 0 en $ regEn 0 en (counter - snatToNum (SNat @ (2 ^ n))))
    twiddled = butterflyLowInput * twiddle

    butterflyHighOutput = butterflyHighInput + twiddled
    butterflyLowOutput  = butterflyHighInput - twiddled 

-- | Example serial FFT decimation in time algorithm. Consumes and produces two complex samples per cycle. Note that both the input and output samples must be supplied in a weird order. See the tests.
fftSerial
    :: forall a. Num a
    => Vec 4 (Complex a)             -- ^ Precomputed twiddle factors
    -> Signal Bool                   -- ^ Input enable signal
    -> Signal (Complex a, Complex a) -- ^ Pair of input samples
    -> Signal (Complex a, Complex a) -- ^ Pair of output samples
fftSerial twiddles en input = 
    fftSerialStep twiddles (de . de . de . de $ en) $ 
    fftSerialStep cexp2    (de en) $ 
    fftBase en input

    where

    de = register False

    cexp2 :: Vec 2 (Complex a)
    cexp2 = halveTwiddles twiddles

    fftBase :: Signal Bool -> Signal (Complex a, Complex a) -> Signal (Complex a, Complex a)
    fftBase en = regEn (0, 0) en . fmap func
        where
        func (x, y) = (x + y, x - y)

