import math
import sys

args = sys.argv

min_tick = -887272
max_tick = 887272

q96 = 2**96
eth = 10**18


def price_to_tick(p):
    return math.floor(math.log(p, 1.0001))


def price_to_sqrtp(p):
    return int(math.sqrt(p) * q96)


def sqrtp_to_price(sqrtp):
    return (sqrtp / q96) ** 2


def tick_to_sqrtp(t):
    return int((1.0001 ** (t / 2)) * q96)


def liquidity0(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return (amount * (pa * pb) / q96) / (pb - pa)


def liquidity1(amount, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return amount * q96 / (pb - pa)


def calc_amount0(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return liq * q96 * (pb - pa) / pb / pa


def calc_amount1(liq, pa, pb):
    if pa > pb:
        pa, pb = pb, pa
    return liq * (pb - pa) / q96




def calc_expected(price_current, liquidity,specified,fee):
    # console.log(string.concat(s, "-for-expected-current-price: "), _priceCurrent);
    # console.log(string.concat(s, "-for-expected-current-liquidity: "), _liquidity);
    # console.log(string.concat(s, "-for-expected-amount0-specified: "), SWAP_PARAMS.amountSpecified < 0 ? -SWAP_PARAMS.amountSpecified : SWAP_PARAMS.amountSpecified);
    # console.log(string.concat(s, "-for-expected-current-fee: "), key.fee);
    sqrtp_cur = int(price_current)
    liq = int(liquidity)
    amount_in = int(specified)
    fee = int(fee)

    price_next = int((liq * q96 * sqrtp_cur) // (liq * q96 + amount_in * sqrtp_cur))

    price_expected = (price_next / q96) ** 2
    sqrtP_expected = price_next
    # return (f"{s}-SWAP-tick expected: {price_to_tick((price_next / q96) ** 2)}", end="\n ")

    amount_in = calc_amount0(liq, price_next, sqrtp_cur)
    amount_out = calc_amount1(liq, price_next, sqrtp_cur) * (1 - fee / 10000)

    return (price_expected, sqrtP_expected, amount_in, amount_out)

def calc_actual():
    # SWAP-exactOut-amount0 delta: -100
    # SWAP-exactOut-amount1 delta: 99
    amount_in = int(args[1])
    amount_out = int(args[2])
    # return (f"{s}-SWAP-price actual: {(amount_out / amount_in):.16f}", end="\n  ")
    return (amount_out / amount_in)



if __name__ == "__main__":
    if len(args) == 5:
        print(calc_expected())
    elif len(args) == 3:
        print(calc_actual())