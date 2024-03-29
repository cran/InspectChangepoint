#' Informative sparse projection for estimation of changepoints (inspect)
#' @description This is the main function of the package InspectChangepoint. The function \code{inspect} estimates the locations of multiple changepoints in the mean structure of a multivariate time series. Multiple changepoints are estimated using a (wild) binary segmentation scheme, whereas each segmentation step uses the \code{\link{locate.change}} function.
#'
#' @param x The input data matrix of a high-dimensional time series, with each component time series stored as a row.
#' @param lambda Regularisation parameter used in \code{\link{locate.change}}.  If no value is supplied, the dafault value is chosen to be log(log(n)*p/2), where p and n are the number of rows and columns of the data matrix x respectively.
#' @param threshold Threshold level for testing whether an identified changepoint is a true changepoint. If no value is supplied, the threshold level is computed via Monte Carlo simulation of 100 repetitions from the null model.
#' @param schatten The Schatten norm constraint to use in the \code{\link{locate.change}} function. Default is schatten = 2, i.e. a Frobenius norm constraint.
#' @param M The Monte Carlo parameter used for wild binary segmentation. Default is M = 0, which means a classical binary segmentation scheme is used.
#' @param missing_data How missing data in x should be handled. If missing_data='meanImpute', then missing data are imputed with row means; if 'MissInspect', use the MissInspect algorithm of Follain et al. (2022)' if 'auto', the program will make the choice depending on the amount of missingness.
#' @param show_progress whether to display progress of computation
#'
#' @details The input time series is first standardised using the \code{\link{rescale.variance}} function. Recursive calls of the \code{\link{locate.change}} function then segments the multivariate time series using (wild) binary segmentation. A changepoint at time z is defined here to mean that the time series has constant mean structure for time up to and including z and constant mean structure for time from z+1 onwards.
#'
#' More details about model assumption and theoretical guarantees can be found in Wang and Samworth (2016). Note that Monte Carlo computation of the threshold value can be slow, especially for large p. If \code{inspect} is to be used multiple times with the same (or similar) data matrix size, it is better to precompute the threshold level via Monte Carlo simulation by calling the \code{\link{compute.threshold}} function.
#'
#' @return The return value is an S3 object of class 'inspect'. It contains a list of two objeccts:
#' \itemize{
#' \item{x }{The input data matrix}
#' \item{changepoints }{A matrix with three columns. The first column contains the locations of estimated changepoints sorted in increasing order; the second column contains the maximum CUSUM statistics of the projected univariate time series associated with each estimated changepoint; the third column contains the depth of binary segmentation for each detected changepoint.}
#' }
#'
#' @references Wang, T. and Samworth, R. J. (2018) High dimensional changepoint estimation via sparse projection. \emph{J. Roy. Statist. Soc., Ser. B}, \strong{80}, 57--83.
#' Follain, B., Wang, T. and Samworth R. J. (2022) High-dimensional changepoint estimation with heterogeneous missingness. \emph{J. Roy. Statist. Soc., Ser. B}, to appear
#'
#' @examples
#' n <- 500; p <- 100; ks <- 30; zs <- c(125,250,375)
#' varthetas <- c(0.2,0.4,0.6); overlap <- 0.5
#' obj <- multi.change(n, p, ks, zs, varthetas, overlap)
#' x <- obj$x
#' threshold <- compute.threshold(n,p)
#' ret <- inspect(x, threshold = threshold)
#' ret
#' summary(ret)
#' plot(ret)
#' @import stats
#' @import graphics
#' @export

inspect <- function(x, lambda, threshold, schatten=c(1, 2), M, missing_data='auto', show_progress=FALSE){
    # basic parameters and initialise
    x <- as.matrix(x)
    if (dim(x)[2] == 1) x <- t(x) # treat univariate time series as a row vector
    if (prod(dim(x)) > 1e6 && !requireNamespace("RSpectra")){
      warning('Dimension of data matrix is large, it is recommend to install the RSpectra package first.')
    }
    p <- dim(x)[1] # dimensionality of the time series
    n <- dim(x)[2] # time length of the observation
    if (missing(lambda)) lambda <- sqrt(log(log(n)*p)/2)
    if (missing(threshold)) threshold <- compute.threshold(n, p, show_progress=show_progress)
    if (missing(schatten)) schatten <- 2
    if (missing(M)) M <- 0
    if (missing(missing_data) || missing_data=='auto'){
        if (mean(is.na(x)) < 0.1) {
            missing_data <- 'meanImpute'
        } else {
            missing_data <- 'MissInspect'
        }
    }

    # mean impute if necessary
    if (missing_data == 'meanImpute'){
        row_means <- rowMeans(x, na.rm=TRUE)
        x[is.na(x)] <- rep(row_means, ncol(x))[is.na(x)]
    }

    x <- rescale.variance(x)

    # generate random time windows of length at least 2
    rnd1 <- sample(0:(n-2), M, replace = TRUE)
    rnd2 <- sample(0:(n-2), M, replace = TRUE)
    window_s <- pmin(rnd1, rnd2)
    window_e <- pmax(rnd1, rnd2) + 2

    # recursive function for binary segmentation
    BinSeg <- function(x, s, e, depth){
        if (e - s <= 2) return(NULL) # stop when the segment has only one point
        ind <- (window_s >= s) & (window_e <= e) # \mathcal{M}_{s,e}
        max.val <- -1
        cp <- 0

        for (m in c(0,((1:M)[ind]))) {
            if (m == 0) {
                s_m <- s
                e_m <- e
            } else {
                s_m <- window_s[m]
                e_m <- window_e[m]
            }

            if (missing_data=='meanImpute'){
                obj <- locate.change(x[,(s_m+1):e_m], lambda, schatten)
            } else {
                obj <- locate.change.missing(x[,(s_m+1):e_m], lambda)
            }
            if (obj$cusum > max.val) {
                max.val <- obj$cusum
                cp <- s_m + obj$changepoint
            }
        }

        # recurse
        ret <- setNames(c(cp, max.val, depth), c('location', 'max.proj.cusum', 'depth'))

        if (max.val < threshold) {
            return(NULL)
        } else {
            if (show_progress) cat('Changepoint identified at', ret['location'], 'with CUSUM', ret['max.proj.cusum'], '\n')
            return(rbind(BinSeg(x, s, cp, depth + 1),
                         ret,
                         BinSeg(x, cp, e, depth + 1)))
        }
    }

    # return all changepoints of x
    ret <- NULL
    ret$x <- x
    ret$changepoints <- BinSeg(x, 0, n, depth=1)
    rownames(ret$changepoints) <- NULL

    class(ret) <- 'inspect'
    return(ret)
}


#' Print function for 'inspect' class objects
#' @param x an 'inspect' class object
#' @param ... other arguments to be passed to methods are not used
#' @seealso \code{\link{inspect}}
#' @export
print.inspect <- function(x, ...){
    print(x$changepoints[, 1])
}


#' Summary function for 'inspect' class objects
#' @param object an 'inspect' class object
#' @param ... other arguments to be passed to methods are not used
#' @seealso \code{\link{inspect}}
#' @export
summary.inspect <- function(object, ...){
    object$changepoints
}


#' Plot function for 'inspect' class objects
#' @param x an 'inspect' class object
#' @param ... other arguments to be passed to methods are not used
#' @seealso \code{\link{inspect}}
#' @export
plot.inspect <- function(x, ...){
        obj <- x
        p <- dim(obj$x)[1]
        n <- dim(obj$x)[2]
        image(1:n, 1:p, t(obj$x), xlab='time', ylab='coordinate', axes=TRUE,
              frame.plot=TRUE)
        result <- as.matrix(obj$changepoints)
        abline(v=result[, 1], col='blue')
    }
