using Lasso, GLM, Distributions, GLMNet, FactCheck

datapath = joinpath(dirname(@__FILE__), "data")

testpath(T::DataType, d::Normal, l::GLM.Link, nsamples::Int, nfeatures::Int) =
    joinpath(datapath, "$(T)_$(typeof(d).name.name)_$(typeof(l).name.name)_$(nsamples)_$(nfeatures).tsv")

function makeX(ρ, nsamples, nfeatures)
    Σ = fill(ρ, nfeatures, nfeatures)
    Σ[diagind(Σ)] = 1
    X = rand(MvNormal(Σ), nsamples)'
    β = [(-1)^j*exp(-2*(j-1)/20) for j = 1:nfeatures]
    (X, β)
end

randdist(::Normal, x) = rand(Normal(x))
randdist(::Binomial, x) = rand(Bernoulli(x))
randdist(::Poisson, x) = rand(Poisson(x))
function genrand(T::DataType, d::Distribution, l::GLM.Link, nsamples::Int, nfeatures::Int)
    X, coef = makeX(0.0, nsamples, nfeatures)
    y = linkinv!(l, Array(T, nsamples), X*coef)
    for i = 1:length(y)
        y[i] = randdist(d, y[i])
    end
    (X, y)
end

facts("LassoPath") do
    for (dist, link) in ((Normal(), IdentityLink()), (Binomial(), LogitLink()), (Poisson(), LogLink()))
        context("$(typeof(dist).name.name) $(typeof(link).name.name)") do
            srand(1337)
            (X, y) = genrand(Float64, dist, link, 1000, 10)
            yoff = randn(length(y))
            for intercept = [false, true]
                context("$(intercept ? "w/" : "w/o") intercept") do
                    for alpha = [1, 0.5]
                        context("alpha = $alpha") do
                            for offset = Vector{Float64}[Float64[], yoff]
                                context("$(isempty(offset) ? "w/" : "w/o") offset") do
                                    # First fit with GLMNet
                                    if isa(dist, Normal)
                                        yp = isempty(offset) ? y : y + offset
                                        ypstd = std(yp, corrected=false)
                                        # glmnet does this on entry. Should we?
                                        yp ./= ypstd
                                        !isempty(offset) && (offset ./= ypstd)
                                        y ./= ypstd
                                        g = glmnet(X, yp, dist, intercept=intercept, alpha=alpha, tol=eps())
                                    elseif isa(dist, Binomial)
                                        yp = zeros(size(y, 1), 2)
                                        yp[:, 1] = y .== 0
                                        yp[:, 2] = y .== 1
                                        g = glmnet(X, yp, dist, intercept=intercept, alpha=alpha, tol=eps(),
                                                   offsets=isempty(offset) ? zeros(length(y)) : offset)
                                    else
                                        g = glmnet(X, y, dist, intercept=intercept, alpha=alpha, tol=eps(),
                                                   offsets=isempty(offset) ? zeros(length(y)) : offset)
                                    end
                                    gbeta = convert(Matrix{Float64}, g.betas)

                                    for naivealgorithm = [false, true]
                                         context(naivealgorithm ? "naive" : "covariance") do
                                            for randomize = VERSION >= v"0.4-dev+1915" ? [false, true] : [false]
                                                context(randomize ? "random" : "sequential") do
                                                    # Now fit with Lasso
                                                    l = fit(LassoPath, X, y, dist, link, λ=g.lambda, naivealgorithm=naivealgorithm, intercept=intercept,
                                                            cd_tol=eps(), irls_tol=eps(), criterion=:coef, randomize=randomize, α=alpha, offset=offset)

                                                    # rd = (l.coefs - gbeta)./gbeta
                                                    # rd[!isfinite(rd)] = 0
                                                    # println("         coefs adiff = $(maxabs(l.coefs - gbeta)) rdiff = $(maxabs(rd))")
                                                    # rd = (l.b0 - g.a0)./g.a0
                                                    # rd[!isfinite(rd)] = 0
                                                    # println("         b0    adiff = $(maxabs(l.b0 - g.a0)) rdiff = $(maxabs(rd))")
                                                    @fact l.coefs => roughly(gbeta, 2e-7)
                                                    @fact l.b0 => roughly(g.a0, 2e-7)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end