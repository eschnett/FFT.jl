module FourierTransforms

using Compat: cispi
using Primes

################################################################################

function direct_ft!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    N = length(x)
    @assert length(X) == N
    RT = typeof(real(zero(T)))
    for k in 1:N
        s = zero(T)
        for n in 1:N
            s += cispi(-2 * ((n - 1) * (k - 1) % N) / RT(N)) * x[n]
        end
        X[k] = s
    end
    return X
end

direct_ft(x::AbstractVector) = direct_ft!(similar(x), x)

################################################################################

function direct_ft_1!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    @assert length(X) == length(x) == 1
    X[1] = x[1]
    return X
end

direct_ft_1(x::AbstractVector) = direct_ft_1!(similar(x), x)

################################################################################

function direct_ft_2!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    @assert length(X) == length(x) == 2
    X[1] = x[1] + x[2]
    X[2] = x[1] - x[2]
    return X
end

direct_ft_2(x::AbstractVector) = direct_ft_2!(similar(x), x)

################################################################################

function direct_ft_4!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    @assert length(X) == length(x) == 4
    X[1] = (x[1] + x[3]) + (x[2] + x[4])
    X[2] = (x[1] - x[3]) - im * (x[2] - x[4])
    X[3] = (x[1] + x[3]) - (x[2] + x[4])
    X[4] = (x[1] - x[3]) + im * (x[2] - x[4])
    return X
end

direct_ft_4(x::AbstractVector) = direct_ft_4!(similar(x), x)

################################################################################

# <https://en.wikipedia.org/w/index.php?title=Cooley%E2%80%93Tukey_FFTur_algorithm&oldid=1056450535>
function ditfft2!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    N = length(x)
    @assert length(X) == N
    RT = typeof(real(zero(T)))
    if N == 0
        # do nothing
    elseif N == 1
        X[1] = x[1]
    else
        # Ensure N is even
        @assert N % 2 == 0
        N2 = N ÷ 2
        ditfft2!((@view X[(0 * N2 + 1):(1 * N2)]), (@view x[1:2:end]))
        ditfft2!((@view X[(1 * N2 + 1):(2 * N2)]), (@view x[2:2:end]))
        for k in 1:N2
            ϕ = cispi(-2 * (k - 1) / RT(N))
            p = X[0 * N2 + k]
            q = ϕ * X[1 * N2 + k]
            X[0 * N2 + k] = p + q
            X[1 * N2 + k] = p - q
        end
    end
    return X
end

ditfft2(x::AbstractVector) = ditfft2!(similar(x), x)

################################################################################

function choose_radix_sqrt(n::Integer)
    @assert n ≥ 0
    n ≤ 1 && return n
    # Handle special cases efficiently
    if ispow2(n)
        # Power of 2
        return 2
    end
    # Power of 2 times a factor
    p2 = trailing_zeros(n)
    factor = n >> p2
    if factor ∈ (3, 5, 7, 11, 13, 17, 19)
        return factor
    end
    # Use a greedy algorithm to find the largest factor not larger than sqrt(n)
    prime_factor_counts = factor(n)
    prime_factors = sort!(collect(keys(prime_factor_counts)))
    sqrt_n = isqrt(n)
    radix = 1
    for prime_factor in Iterators.reverse(Iterators.filter(≤(sqrt_n), prime_factors))
        for count in 1:prime_factor_counts[prime_factor]
            if radix * prime_factor ≤ sqrt_n
                radix *= prime_factor
            else
                break
            end
        end
    end
    # Always return a radix larger than 1
    radix == 1 && return n
    return radix
end

# X: output
# Y: workspace
# x: input (will be destroyed)
function radix_fft!(X::AbstractVector{T}, Y::AbstractVector{T}, x::AbstractVector{T};
                    choose_radix=choose_radix_sqrt) where {T<:Complex}
    N = length(x)
    @assert length(X) == length(Y) == N
    RT = typeof(real(zero(T)))
    radix = choose_radix(N)
    if N == 0
        # do nothing
    elseif N ≤ radix
        direct_ft!(X, x)
    else
        N₁ = radix              # aka "decimation in time"
        @assert N % N₁ == 0
        N₂ = N ÷ N₁
        x2 = reshape(x, (N₁, N₂))
        X2 = reshape(X, (N₂, N₁))
        Y2 = reshape(Y, (N₂, N₁))
        Z2 = reshape(x, (N₂, N₁))
        for n₁ in 1:N₁
            radix_fft!((@view Y2[:, n₁]), (@view X2[:, n₁]), (@view x2[n₁, :]); choose_radix=choose_radix)
            for n₂ in 1:N₂
                Y2[n₂, n₁] *= cispi(-2 * (n₁ - 1) * (n₂ - 1) / RT(N))
            end
        end
        for n₂ in 1:N₂
            radix_fft!((@view X2[n₂, :]), (@view Z2[n₂, :]), (@view Y2[n₂, :]); choose_radix=choose_radix)
        end
    end
    return X
end

"x will contain output"
radix_fft!(x::AbstractVector; kws...) = radix_fft!(x, similar(x), copy(x); kws...)
"X will contain output, x will be preserved"
radix_fft!(X::AbstractVector, x::AbstractVector; kws...) = radix_fft!(X, similar(x), copy(x); kws...)
"x will be preserved"
radix_fft(x::AbstractVector; kws...) = radix_fft!(similar(x), x; kws...)

################################################################################

export fft!, fft, inv_fft!, inv_fft

"""
    fft!(X::AbstractVector, x::AbstractVector)

Calculate the Fourier transform of `x` and store it into `X`. `x` is
not modified. Both vectors must have the same length and must have
complex element types.

See also: [`fft`](@ref), [`inv_fft!`](@ref).
"""
fft!(X::AbstractVector, x::AbstractVector) = radix_fft!(X, x)

"""
    inv_fft!(x::AbstractVector, X::AbstractVector)

Calculate the inverse Fourier transform of `X` and store it into `x`.
`X` is not modified. Both vectors must have the same length and must
have complex element types.

See also: [`inv_fft`](@ref), [`fft!`](@ref).
"""
function inv_fft!(X::AbstractVector{T}, x::AbstractVector{T}) where {T<:Complex}
    # TODO: Don't modify `x`
    x .= conj(x)
    fft!(X, x)
    x .= conj(x)
    X .= conj(X) / length(X)
    return X
end

"""
    X = fft(x::AbstractVector)
    X::AbstractVector

Calculate the Fourier transform of `x` and return it in a newly
allocate vector. `x` is not modified. The element type of `x` must be
a complex number type.

See also: [`inv_fft`](@ref), [`fft!`](@ref).
"""
fft(x::AbstractVector) = fft!(similar(x), x)

"""
    x = inv_fft(X::AbstractVector)
    x::AbstractVector

Calculate the inverse Fourier transform of `X` and return it in a
newly allocate vector. `X` is not modified. The element type of `X`
must be a complex number type.

See also: [`fft`](@ref), [`inv_fft!`](@ref).
"""
inv_fft(x::AbstractVector) = inv_fft!(similar(x), x)

end
