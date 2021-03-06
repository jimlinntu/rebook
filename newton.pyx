# cython: boundscheck=False
# cython: wraparound=False
# cython: nonecheck=False
# cython: cdivision=True

from __future__ import division
import numpy as np
cimport numpy as np
cimport libc.math
from libc.math cimport fabs, fma, INFINITY, isfinite

cimport cython

from numpy.polynomial.polynomial import Polynomial as Poly

cdef double poly_eval_verbose(np.ndarray[np.float64_t, ndim=1] coef, double x):
    cdef double y = 0
    cdef int k, m = coef.shape[0] - 1
    for k in range(m, -1, -1):
        y = fma(y, x, coef[k])  # y * x + a_k
        print k, y, x, coef[k]

    return y

cdef double poly_eval(np.ndarray[np.float64_t, ndim=1] coef, double x):
    cdef double y = 0
    cdef int k, m = coef.shape[0] - 1
    # Horner's rule
    for k in range(m, -1, -1): # k \in [n-1, 0]
        y = fma(y, x, coef[k])  # y * x + a_k

    return y

cdef np.ndarray[np.float64_t, ndim=1] deriv(np.ndarray[np.float64_t, ndim=1] g_coef):
    return g_coef[1:] * np.arange(1, g_coef.shape[0])

# solve: g([R(pt - Of)]_x - T) = [R(pt - Of)]_z
#  g(ray[0] * t - ROf_x) = ray[2] * t - ROf_z
#  g(t) = h(w * t) / w
#  g'(t) = h'(w * t)
#
#   u = w * (Rp_x * t - ROf_x - T); t = (u / w + ROf_x + T) / Rp_x
#
#   s(t)  = g(Rp_x * t - ROf_x - T) - (Rp_z * t - ROf_z)
#         = h(u) / w - (Rp_z * t - ROf_z)
#   s'(t) = g'(Rp_x * t - ROf_x - T) * Rp_x - Rp_z
#         = h'(u) * Rp_x - Rp_z
#
#   s(u)  = h(u) / w - (Rp_z / Rp_x * (u / w + ROf_x + T) - ROf_z)
cdef double find_t(np.ndarray[np.float64_t, ndim=1] h_coef,
                   np.ndarray[np.float64_t, ndim=1] hp_coef,
                   double w, double T,
                   double ROf_x, double ROf_z,
                   double Rp_x, double Rp_z,
                   double t0):
    cdef int done
    cdef double t, y, yp, t_out, u_minus, u_plus, y_minus, y_plus, best_t
    cdef int j
    cdef np.ndarray[np.float64_t, ndim=1] s_coef, roots_t, roots_t_neg
    cdef np.ndarray roots_u

    if not isfinite(T):
        T = 0.

    done = False
    if isfinite(t0):
        t = t0
        for j in range(30):
            u = w * (Rp_x * t - ROf_x - T)
            # y = s(u)
            y = poly_eval(h_coef, u) / w - fma(Rp_z, t, -ROf_z)
            if fabs(y) < 1e-6: # if s(u) is close to zero, we are done
                # print j
                break
            # otherwise, we compute y / y' and perform  t <- t - y / y'
            # Note: s(t) / s'(t) = s(u) / s'(u)
            yp = fma(poly_eval(hp_coef, u), Rp_x, -Rp_z)
            t -= y / yp

        u_minus = w * (Rp_x * t * 0.99 - ROf_x - T)
        y_minus = poly_eval(h_coef, u_minus) / w - fma(Rp_z, t * 0.99, -ROf_z)
        u_plus = w * (Rp_x * t * 0.01 - ROf_x - T)
        y_plus = poly_eval(h_coef, u_plus) / w - fma(Rp_z, t * 0.01, -ROf_z)
        # s(u-) * s(u+) > 0 and y is close enough to zero, we can stop here
        if y_minus * y_plus > 0 and fabs(y) < 1e-6:  # same sign, not obv an intermediate root
            done = True
        else:
            pass  # print 'warning: need to check all roots!'

    if not done:
        # print 'checking all roots...'
        # s_coef == s(u) = h(u) / w - (Rp_z / Rp_x * (u / w + ROf_x + T) - ROf_z)
        s_coef = h_coef / w
        s_coef[1] -= Rp_z / Rp_x / w
        s_coef[0] += ROf_z - Rp_z / Rp_x * (ROf_x + T)

        s_poly = Poly(s_coef)
        roots_u = s_poly.roots() # diretly solve s(u)
        # the author just us the roots whose imagination part is small enough as the solution
        roots_t = (roots_u[abs(roots_u.imag) < 1e-7].real / w + ROf_x + T) / Rp_x
        # Cuz our document plane is on the right side (t < 0), so the author remove t > 0 cases
        roots_t_neg = roots_t[roots_t < 0]
        if roots_t_neg.shape[0] > 0:
            t = -INFINITY
            for j in range(roots_t_neg.shape[0]):
                # choose the largest t over negative ts
                # (it makes sense, because you want your document be closer to the document
                if roots_t_neg[j] > t:
                    t = roots_t_neg[j]

        # for j in range(10):
        #     u = w * (Rp_x * t - ROf_x - T)
        #     y = poly_eval(h_coef, u) / w - fma(Rp_z, t, -ROf_z)
        #     if fabs(y) < 1e-4:
        #         # print j
        #         break
        #     yp = fma(poly_eval(hp_coef, u), Rp_x, -Rp_z)
        #     t -= y / yp

    t_out = t

    # if the t_out is still not finite, we will use t \in [-2.0, 0] to perform Newton method again
    if not isfinite(t_out):
        # print 'escape hatch'
        best_t = -INFINITY
        for t0 in np.linspace(0, -2.0, 10):
            t = t0
            for j in range(50):
                u = w * (Rp_x * t - ROf_x - T)
                y = poly_eval(h_coef, u) / w - fma(Rp_z, t, -ROf_z)
                if fabs(y) < 1e-8: break
                yp = fma(poly_eval(hp_coef, u), Rp_x, -Rp_z)
                t -= y / yp

            # print('{: .4f} {: .4f} {: .8f}'.format(t0, t, y))
            # if best_t > 0 and t < 0, we directly choose t < 0 because t > 0 must be wrong
            # if |t| < |best_t| + 1e-5(do know why bother to add 1e-5)
            if (best_t > 0 and t < 0) or fabs(t) < fabs(best_t) + 1e-5:
                best_t = t

        t_out = best_t

    return t_out

# g(x) = 1/w h(wx)
# g'(x) = h'(wx)
def t_i_k(np.ndarray[np.float64_t, ndim=2] R,
          g,
          np.ndarray[np.float64_t, ndim=2] points,
          np.ndarray[np.float64_t, ndim=1] t0s):

    cdef np.ndarray[np.float64_t, ndim=1] ts, Of, ROf
    cdef np.ndarray[np.float64_t, ndim=1] hl_coef, hlp_coef, hr_coef, hrp_coef
    cdef np.ndarray[np.float64_t, ndim=2] rays

    cdef double f = 3270.5
    cdef double ROf_x, ROf_y, ROf_z, Rp_x, Rp_y, Rp_z

    cdef int n, i, big_ys
    cdef double t, y, u, t0, big_ys_sum, tl, tr, yl = INFINITY, yr = INFINITY
    cdef double w, T

    cdef int dual = g.split() # if the polynomial can be split

    rays = R.dot(points) # R dot p

    Of = np.array([0, 0, f], dtype=np.float64)
    ROf = R.dot(Of)
    ROf_x, ROf_z = ROf[0], ROf[2]

    ts = np.zeros((points.shape[1],), dtype=np.float64)
    n = ts.shape[0]
    assert n == t0s.shape[0]

    if dual:
        T = g.T
        gl = g.left
        gr = g.right
        assert gl.degree() == gr.degree()
        hr_coef = gr.h.coef.copy()
        hr_coef[0] = 0
        hrp_coef = deriv(hr_coef)
    else:
        T = INFINITY
        gl = g

    w = gl.omega

    # defer interior scaling until computation
    hl_coef = gl.h.coef.copy()
    hl_coef[0] = 0
    # h_left prime == hl'()
    hlp_coef = deriv(hl_coef)

    if np.all(hl_coef == 0.) and (not dual or np.all(hr_coef == 0.)):
        ts = ROf_z / rays[2]
        return ts, ts * rays - ROf[:, np.newaxis]

    big_ys = 0
    big_ys_sum = 0

    for i in range(n):
        Rp_x = rays[0, i]
        Rp_z = rays[2, i]

        t0 = t0s[i] # initial t for Newton method
        if not dual:
            # solve: [X, Y, Z] = R p t - R Of in the paper
            t = find_t(hl_coef, hlp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
        elif False:  # isfinite(t0) and Rp_x * t0 - ROf_x < T - 1:
            tl = find_t(hl_coef, hlp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
            if Rp_x * tl - ROf_x < T:
                t = tl
            else:
                tr = find_t(hr_coef, hrp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
                t = max(tl, tr)
        elif False:  # isfinite(t0) and Rp_x * t0 - ROf_x > T + 1:
            tr = find_t(hr_coef, hrp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
            if Rp_x * tr - ROf_x < T:
                t = tr
            else:
                tl = find_t(hl_coef, hlp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
                t = max(tl, tr)
        else:
            tl = find_t(hl_coef, hlp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
            tr = find_t(hr_coef, hrp_coef, w, T, ROf_x, ROf_z, Rp_x, Rp_z, t0)
            # if both tl, tr are smaller than zero, we can two solutions to the GCS surface
            if tl < 0 and tr < 0:
                xl = Rp_x * tl - ROf_x
                xr = Rp_x * tr - ROf_x
                if xl < T and xr > T:
                    '''
                        Because the GCS might be look like this:
                          h_left     h_right
                            \         /
                             \       /
                              \     /
                               \   /
                                \ /
                         ------------- (below is the part we do not want)
                                 /\
                                /  \
                               /    \
                              /      \

                        when we solve tl and tr, we might find a solution that is deeper(more negative)
                        Therefore, when we consider (tl-(-1)) and (tr-(-1)), we are computing the distance of t to -1
                        as we know, t = -1 should be very likely close to our solution
                        Thus, fabs(tl + 1) < fabs(tr + 1) says: if tl is closer to -1, then we consider tl,
                        otherwise we choose tr
                    '''
                    t = tl if fabs(tl + 1) < fabs(tr + 1) else tr
                else:
                    # if both xl and xr are on the same side, we just choose tl if xl < T
                    t = tl if xl < T else t
                # if fabs(y) > 1e-4:
                #     print '{:1.3f} {:4.0f}; {:1.3f} {:4.0f}'.format(tl, xl, tr, xr)
            else:
                # if one of tl, tr is < 0, we choose the negative one (because > 0 is obvious false)
                t = min(tl, tr)

        assert isfinite(t)
        ts[i] = t
        # if T == inf, u == -inf
        u = w * (Rp_x * t - ROf_x - T)
        # if u == -inf, y = nan (Note: fabs(nan) > 1e-4 is False)
        y = fabs(poly_eval(hl_coef, u) / w - fma(Rp_z, t, -ROf_z))
        if dual:
            yr = fabs(poly_eval(hr_coef, u) / w - fma(Rp_z, t, -ROf_z))
            y = min(y, yr)

        if fabs(y) > 1e-4:
            # print 'big y 2!', y
            big_ys += 1
            big_ys_sum += y

        t0s[i] = ts[i] # save current t for later usage

    # print 'final ts:', ts
    if big_ys > 0:
        print 'big ys:', big_ys, 'avg:', big_ys_sum / big_ys

    # ts, ts(N, ) * rays(3, N) - ROf[:, np.newaxis](3, 1)(the point on GCS surface)
    return ts, ts * rays - ROf[:, np.newaxis]
