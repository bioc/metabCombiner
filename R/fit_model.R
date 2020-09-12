#' Format List of RT Ordered Pairs
#'
#' @param object metabCombiner object
#'
#' @param anchors data.frame of ordered pair features for RT fitting
#'
#' @param weights numeric fit weights
#'
#' @param useID  logical. Option to use matched IDs to inform fit
#'
#' @noRd
formatAnchors <- function(object, anchors, weights, useID){
    if(!useID | is.null(anchors[["labels"]]))
        anchors[["labels"]] = "A"
    cTable = combinedTable(object)
    rtx <- c(min(cTable[["rtx"]]), anchors[["rtx"]], max(cTable[["rtx"]]))
    rty <- c(min(cTable[["rty"]]), anchors[["rty"]], max(cTable[["rty"]]))
    labels <- c("I", anchors[["labels"]], "I")
    if(length(weights) == nrow(anchors))
        weights = c(1, weights, 1)

    rts <- data.frame(rtx, rty, labels, weights, stringsAsFactors = FALSE)
    return(rts)
}

#' @title Filter Outlier Ordered Pairs
#'
#' @description
#' Helper function for \code{\link{fit_gam}} & \code{\link{fit_loess}}. It
#' filters the set of ordered pairs using the residuals calculated from
#' multiple GAM / loess fits.
#'
#' @param rts  Data frame of ordered retention time pairs.
#'
#' @param fit  Either "gam" for GAM fits, or "loess" for loess fits
#'
#' @param vals numeric values: k values for GAM fits, spans for loess fits
#'
#' @param iterFilter integer number of residual filtering iterations
#'
#' @param ratio numeric. A point is an outlier if the ratio of residual to
#' mean residual of a fit exceeds this value. Must be greater than 1.
#'
#' @param frac  numeric. A point is excluded if deemed a residual in more than
#' this fraction value times the number of fits. Must be between 0 & 1.
#'
#' @param bs character. Choice of spline method from mgcv; either "bs" or "ps"
#'
#' @param m integer. Basis and penalty order for GAM; see ?mgcv::s
#'
#' @param family character. Choice of mgcv family; see: ?mgcv::family.mgcv
#'
#' @param method character. Smoothing parameter estimation method; see:
#' ?mgcv::gam
#'
#' @param optimizer character. Method to optimize smoothing parameter; see:
#' ?mgcv::gam
#'
#' @param loess.pars parameters for LOESS fitting; see ?loess.control
#'
#' @param ... other arguments passed to \code{mgcv::gam}.
#'
#' @return anchor rts data frame with updated weights.
filterAnchors <- function(rts, fit, vals, iterFilter, ratio, frac, bs, m,
                            family, method, optimizer, loess.pars, ...)
{
    iteration = 0
    while(iteration < iterFilter){
        cat("Performing filtering iteration: ", iteration + 1, "\n", sep = "")
        if(fit == "gam")
            residuals <- suppressWarnings(vapply(vals, function(v){
                model <- mgcv::gam(rty ~ s(rtx, k = v, bs = bs, m = m,...),
                                data = rts, family = family, method = method,
                                weights = rts[["weights"]],
                                optimizer = c("outer", optimizer), ...)

                res = abs(model[["fitted.values"]] - model[["y"]])
                return(res)
            }, numeric(nrow(rts))))
        else if(fit == "loess")
            residuals <- suppressWarnings(vapply(vals, function(v){
                model <- stats::loess(rty ~ rtx, data = rts, span = v,
                                    degree = 1, weights = rts$weights,
                                    control = loess.pars, family = "s")

                res = abs(model[["residuals"]])
                return(res)
            }, numeric(nrow(rts))))

        include = which(rts[["weights"]] == 1)
        thresholds <- ratio * colMeans(residuals[include,] %>% as.matrix())

        flags <- vapply(seq(1,length(vals)), function(i){
            fl <- (residuals[,i] > thresholds[i])
            return(fl)
        },logical(nrow(residuals)))

        fracs = rowSums(flags)/ncol(flags)
        remove = fracs > frac
        remove[rts[["labels"]] == "I"] = FALSE

        if(sum(!remove) > 22 & sum(!remove) < length(remove))
            rts$weights[remove] = 0
        else
            break
        iteration = iteration+1
    }

    return(rts)
}

#' @title Cross Validation for Model Fits
#'
#' @description
#' Helper function for \code{fit_gam()} & \code{fit_loess()}. Determines
#' optimal value of \code{k} basis functions for Generalized Additive Model
#' fits or \code{span} for loess fits from among user-defined choices,
#' using a 10-fold cross validation minimizing mean squared error.
#'
#' @param rts data.frame of ordered pair retention times
#'
#' @param fit  Either "gam" for GAM fits, or "loess" for loess fits
#'
#' @param vals numeric vector: k values for GAM fits, spans for loess fits.
#' Best value chosen by 10-fold cross validation.
#'
#' @param bs character. Choice of spline method, either "bs" or "ps"
#'
#' @param family character. Choice of mgcv family; see: ?mgcv::family.mgcv
#'
#' @param m integer. Basis and penalty order for GAM; see ?mgcv::s
#'
#' @param method character. Smoothing parameter estimation method; see:
#' ?mgcv::gam
#'
#' @param optimizer  character. Method to optimize smoothing parameter; see:
#' ?mgcv::gam
#'
#' @param loess.pars parameters for LOESS fitting; see ?loess.control
#'
#' @param ... Other arguments passed to \code{mgcv::gam}.
#'
#' @return Optimal parameter value as determined by 10-fold cross validation
crossValFit <- function(rts, fit, vals, bs, family, m, method, optimizer,
                        loess.pars,...)
{
    cat("Performing 10-fold cross validation\n")
    rts = dplyr::filter(rts, .data$weights != 0)
    N = nrow(rts) - 1
    folds <- caret::createFolds(seq(2,N), k = 10, returnTrain = FALSE)

    cv_errors <- vapply(folds, function(f){
        f = f + 1
        rts_train <- rts[-f,]
        rts_test <- rts[f,]

        #error for each span for fold f
        errors <- suppressWarnings(vapply(vals, function(v){
            if(fit == "gam")
                model <- mgcv::gam(rty ~ s(rtx, k = v, bs = bs, m = m, ...),
                            data = rts_train, family = family, method = method,
                            optimizer = c("outer",optimizer),
                            weights = rts_train$weights, ...)
            else if (fit == "loess")
                model <- stats::loess(rty ~ rtx, data = rts_train, span = v,
                                    degree = 1, weights = rts_train$weights,
                                    control = loess.pars,  family = "s")

            preds <- stats::predict(model, newdata = rts_test)
            MSE = sum((preds - rts_test[["rty"]])^2)/ length(preds)

            return(MSE)
        }, numeric(1)))

        return(errors)
    }, numeric(length(vals)))

    mean_cv_errors = rowMeans(matrix(cv_errors, nrow = length(vals)))
    best_val = vals[which.min(mean_cv_errors)]
    return(best_val)
}

#' @title Fit RT Projection Model With GAMs
#'
#' @description
#' Fits a (penalized) basis splines curve through a set of ordered pair
#' retention times, modeling one set of retention times (rty) as a function
#' on the other set (rtx).Filtering iterations of high residual points are
#' performed first. Multiple acceptable values of \code{k} can be supplied
#' used, with one value selected through 10-fold cross validation.
#'
#' @param object  a metabCombiner object.
#'
#' @param useID  logical. Option to use matched IDs to inform fit
#'
#' @param k  integer vector values controling the number of basis functions for
#' GAM construction. Best value chosen by 10-fold cross validation.
#'
#' @param ratio numeric. A point is an outlier if the ratio of residual to
#' mean residual of a fit exceeds this value. Must be greater than 1.
#'
#' @param frac  numeric. A point is excluded if deemed a residual in more than
#' this fraction value times the number of fits. Must be between 0 & 1.
#'
#' @param iterFilter integer number of residual filtering iterations to perform
#'
#' @param bs   character. Choice of spline method from mgcv, either "bs" (basis
#' splines) or "ps" (penalized basis splines)
#'
#' @param family character. Choice of mgcv family; see: ?mgcv::family.mgcv
#'
#' @param weights Optional user supplied weights for each ordered pair. Must be
#' of length equal to number of anchors (n) or a divisor of (n + 2).
#'
#' @param m  integer. Basis and penalty order for GAM; see ?mgcv::s
#'
#' @param method  character. Smoothing parameter estimation method; see:
#' ?mgcv::gam
#'
#' @param optimizer character. Method to optimize smoothing parameter; see:
#' ?mgcv::gam
#'
#' @param ... Other arguments passed to \code{mgcv::gam}.
#'
#' @details
#' A set of ordered pair retention times must be previously computed using
#' \code{selectAnchors()}. The minimum and maximum retention times from both
#' input datasets are included in the set as ordered pairs (min_rtx, min_rty)
#' & (max_rtx, max_rty).
#'
#' The \code{weights} argument initially determines the contribution of each
#' point to the model fits; they are equally weighed by default, but can be
#' changed using an \code{n+2} length vector, where n is the number of ordered
#' pairs and the first and last of the weights determines the contribution of
#' the min and max ordered pairs.
#'
#' The model complexity is determined by \code{k}. Multiple values of k are
#' allowed, with the best value chosen by 10 fold cross validation. Before
#' this happens, certain ordered pairs are removed based on the model errors.
#' In each iteration, a GAM is fit using each selected value of k. A point is
#' "removed" (its corresponding \code{weights} value set to 0) if its residual
#' is \code{ratio} times average residual for a fraction of fitted models, as
#' determined by \code{frac}. If an ordered pair is an "identity" (discovered
#' in the \code{selectAnchors} by setting the \code{useID} to TRUE), then
#' setting \code{useID} here will prevent its removal.
#'
#' Other arguments, e.g. \code{family}, \code{m}, \code{optimizer}, \code{bs},
#' and \code{method} are GAM specific parameters. The \code{family} option is
#' currently limited to the "scat" (scaled t) and "gaussian" families; scat
#' family model fits are more robust to outliers than gaussian fits, but
#' compute much slower. Type of splines are currently limited to basis splines
#' (\eqn{bs = "bs"}) or penalized basis splines (\eqn{bs = "ps"}).
#'
#' @return metabCombiner with a fitted GAM model object
#'
#' @seealso
#' \code{\link{selectAnchors}},\code{\link{fit_loess}},
#'
#' @examples
#' data(plasma30)
#' data(plasma20)
#'
#' p30 <- metabData(plasma30, samples = "CHEAR")
#' p20 <- metabData(plasma20, samples = "Red", rtmax = 17.25)
#' p.comb = metabCombiner(xdata = p30, ydata = p20, binGap = 0.0075)
#'
#' p.comb = selectAnchors(p.comb, tolmz = 0.003, tolQ = 0.3, windy = 0.02)
#' anchors = getAnchors(p.comb)
#'
#' #version 1: using faster, but less robust, gaussian family
#' p.comb = fit_gam(p.comb, k = c(10,12,15,17,20), frac = 0.5,
#'     family = "gaussian")
#'
#' \dontrun{
#' #version 2: using slower, but more robust, scat family
#' p.comb = fit_gam(p.comb, k = seq(12,20,2), family = "scat",
#'                      iterFilter = 1, ratio = 3, method = "GCV.Cp")
#'
#' #version 3 (with identities)
#' p.comb = selectAnchors(p.comb, useID = TRUE)
#' anchors = getAnchors(p.comb)
#' p.comb = fit_gam(p.comb, useID = TRUE, k = seq(12,20,2), iterFilter = 1)
#'
#' #version 4 (using identities and weights)
#' weights = ifelse(anchors$labels == "I", 2, 1)
#' p.comb = fit_gam(p.comb, useID = TRUE, k = seq(12,20,2),
#'                      iterFilter = 1, weights = weights)
#'
#' #version 5 (assigning weights to the boundary points
#' weights = c(2, rep(1, nrow(anchors)), 2)
#' p.comb = fit_gam(p.comb, k = seq(12,20,2), weights = weights)
#'
#' #to preview result of fit_gam
#' plot(p.comb, xlab = "CHEAR Plasma (30 min)",
#'      ylab = "Red-Cross Plasma (20 min)", pch = 19,
#'      main = "Example fit_gam Result Fit")
#' }
#'
#' @export
fit_gam <- function(object, useID = FALSE, k = seq(10,20, by = 2),
                    iterFilter = 2, ratio = 2, frac = 0.5, bs = c("bs", "ps"),
                    family = c("scat", "gaussian"), weights = 1, m = c(3,2),
                    method = "REML", optimizer = "newton", ...)
{
    combinerCheck(isMetabCombiner(object), "metabCombiner")
    anchors = object@anchors
    check_fit_pars(anchors = anchors, fit = "gam", useID = useID, k = k,
                    iterFilter = iterFilter, ratio = ratio, frac = frac)

    ##gam parameters
    bs = match.arg(bs)
    family = match.arg(family)

    rts = formatAnchors(object, anchors, weights, useID)
    rts = filterAnchors(rts = rts, fit = "gam", vals = k, ratio = ratio,
                        frac = frac, iterFilter = iterFilter, bs = bs, m = m,
                        family = family,method = method, optimizer = optimizer,
                        ...)

    if(length(k) > 1)
        best_k <- crossValFit(rts = rts, vals = k, fit = "gam", bs = bs, m = m,
                                family = family, method = method,
                                optimizer = optimizer,...)
    else
        best_k = k

    cat("Fitting Model with k =", best_k, "\n")
    best_model <- mgcv::gam(rty ~ s(rtx, k = best_k, bs = bs, m = m, ...),
                            data = rts, family = family, method = method,
                            optimizer = c("outer", optimizer),
                            weights = rts[["weights"]], ...)

    anchors[["rtProj"]] = stats::predict(best_model, anchors)
    object@anchors = anchors
    object@model[["gam"]] = best_model
    object@stats[["best_k"]] = best_k
    return(object)
}


#' @title Fit RT Projection Model With LOESS
#'
#' @description
#' Fits a local regression smoothing spline curve through a set of ordered pair
#' retention times. modeling one set of retention times (rty) as a function
#' on the other set (rtx). Filtering iterations of high residual points are
#' performed first. Multiple acceptable values of \code{span} can be used, with
#' one value selected through 10-fold cross validation.
#'
#' @param object  metabCombiner object.
#'
#' @param useID  logical. Option to use matched IDs to inform fit
#'
#' @param spans numeric span values (between 0 & 1) used for loess fits
#'
#' @param ratio numeric. A point is an outlier if the ratio of residual to
#' mean residual of a fit exceeds this value. Must be greater than 1.
#'
#' @param frac  numeric. A point is excluded if deemed a residual in more than
#' this fraction value times the number of fits. Must be between 0 & 1.
#'
#' @param iterFilter integer number of residual filtering iterations to perform
#'
#' @param iterLoess  integer. Number of robustness iterations to perform in
#'                   \code{loess()}.See ?loess.control for more details.
#'
#' @param weights Optional user supplied weights for each ordered pair. Must be
#' of length equal to number of anchors (n) or a divisor of (n + 2).
#'
#' @return \code{metabCombiner} object with \code{model} slot updated to
#' contain the fitted loess model
#'
#' @seealso
#' \code{\link{selectAnchors}},\code{\link{fit_gam}}
#'
#' @examples
#' data(plasma30)
#' data(plasma20)
#'
#' p30 <- metabData(plasma30, samples = "CHEAR")
#' p20 <- metabData(plasma20, samples = "Red", rtmax = 17.25)
#' p.comb = metabCombiner(xdata = p30, ydata = p20, binGap = 0.0075)
#' p.comb = selectAnchors(p.comb, tolmz = 0.003, tolQ = 0.3, windy = 0.02)
#'
#' #version 1
#' p.comb = fit_loess(p.comb, spans = seq(0.2,0.3,0.02), iterFilter = 1)
#'
#' #version 2 (using weights)
#' anchors = getAnchors(p.comb)
#' weights = c(2, rep(1, nrow(anchors)), 2)  #weight = 2 to boundary points
#' p.comb = fit_loess(p.comb, spans = seq(0.2,0.3,0.02), weights = weights)
#'
#' #version 3 (using identities)
#' p.comb = selectAnchors(p.comb, useID = TRUE, tolmz = 0.003)
#' p.comb = fit_loess(p.comb, spans = seq(0.2,0.3,0.02), useID = TRUE)
#'
#' #to preview result of fit_loess
#' plot(p.comb, fit = "loess", xlab = "CHEAR Plasma (30 min)",
#'      ylab = "Red-Cross Plasma (20 min)", pch = 19,
#'      main = "Example fit_loess Result Fit")
#'
#' @export
fit_loess <- function(object, useID = FALSE, spans = seq(0.2, 0.3, by = 0.02),
                        iterFilter = 2, ratio = 2, frac = 0.5, iterLoess = 10,
                        weights = 1)
{
    combinerCheck(isMetabCombiner(object), "metabCombiner")
    anchors = object@anchors

    check_fit_pars(anchors = anchors, fit = "loess", useID = useID,
                    iterFilter = iterFilter, ratio = ratio, frac = frac,
                    iterLoess = iterLoess, spans = spans)

    loess.pars = loess.control(iterations = iterLoess, surface = "direct")
    rts = formatAnchors(object, anchors, weights, useID)

    rts = filterAnchors(rts = rts, fit = "loess", iterFilter = iterFilter,
                        ratio = ratio, frac = frac, vals = spans,
                        loess.pars = loess.pars)

    if(length(spans) > 1)
        best_span <- crossValFit(rts = rts, fit = "loess", vals = spans,
                                loess.pars = loess.pars)
    else
        best_span = spans

    cat("Fitting Model with span =", best_span,"\n")

    best_model <- loess(rty ~ rtx, data = rts, span = best_span, degree = 1,
                        family = "symmetric", control = loess.pars,
                        weights = rts[["weights"]])

    anchors[["rtProj"]] = stats::predict(best_model, anchors)
    object@anchors = anchors
    object@model[["loess"]] = best_model
    object@stats[["best_span"]] = best_span
    return(object)
}



