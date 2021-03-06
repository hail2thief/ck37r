#' Impute missing values in a dataframe and add missingness indicators.
#'
#' @description Impute missing values, using knn by default or alternatively
#'   median-impute numerics, mode-impute factors. Add missingness indicators.
#'
#' @param data Dataframe or matrix.
#' @param type "knn" or "standard" (median/mode). NOTE: knn will result in the
#'   data being centered and scaled!
#' @param add_indicators Add a series of missingness indicators.
#' @param prefix String to add at the beginning of the name of each missingness
#'   indicator.
#' @param skip_vars List of variable names to exclude from the imputation.
#' @param all_vars Calculate imputation value for all variables, in cases where
#'   the imputation info may be used for future datasets.
#' @param remove_constant Remove constant missingness indicators, if applicable.
#' @param remove_collinear Remove collinear missingness indicators, if
#'   applicable.
#' @param values Named list with imputation value to use from another dataset.
#' @param verbose If True display extra information during execution.
#'
#'
#' @return List with the following elements:
#' \itemize{
#' \item $data - imputed dataset.
#' \item $impute_info - if knn, caret preprocess element for imputing test data.
#' \item $impute_values - if standard, list of imputation values for each
#'   variable.
#' }
#'
#' @examples
#'
#' # Load a test dataset.
#' data(PimaIndiansDiabetes2, package = "mlbench")
#'
#' # Check for missing values.
#' colSums(is.na(PimaIndiansDiabetes2))
#'
#' # Impute missing data and add missingness indicators.
#' # Don't impute the outcome though.
#' result = impute_missing_values(PimaIndiansDiabetes2, skip_vars = "diabetes")
#'
#' # Confirm we have no missing data.
#' colSums(is.na(result$data))
#'
#'
#' #############
#' # K-nearest neighbors imputation
#'
#' result2 = impute_missing_values(PimaIndiansDiabetes2, type = "knn",
#'                                 skip_vars = "diabetes")
#'
#' # Confirm we have no missing data.
#' colSums(is.na(result2$data))
#'
#' @seealso \code{\link{missingness_indicators}} \code{\link[caret]{preProcess}}
#'
#' @importFrom stats median
#' @importFrom RANN nn2
#'
#' @export
impute_missing_values =
  function(data,
           type = "standard",
           add_indicators = TRUE,
           prefix = "miss_",
           skip_vars = NULL,
           all_vars = FALSE,
           remove_constant = TRUE,
           remove_collinear = TRUE,
           values = NULL,
           verbose = FALSE) {

  # Loop over each feature.
  missing_indicators = NULL

  # Make a copy to store the imputed dataframe.
  new_data = data

  # Only check variables that we don't want to skip.
  non_skipped_vars = !colnames(data) %in% skip_vars

  # List of results to populate.
  # Save our configuration first.
  results = list(type = type,
                 add_indicators = add_indicators,
                 skip_vars = skip_vars,
                 prefix = prefix)

  # Identify columns with any NAs.
  # We apply skip_vars within the function so that which() indices are correct.
  any_nas = which(sapply(colnames(data),
                         function(col) !col %in% skip_vars && anyNA(data[[col]])))

  if (verbose) {
    cat("Found", length(any_nas), "variables with NAs.\n")
  }

  if (type == "standard") {
    if (verbose) {
      cat("Running standard imputation.\n")
    }

    # List to save the imputation values used.
    # We need a list because it can contain numerics and factors.
    impute_values = vector("list", sum(non_skipped_vars))

    # Copy variable names into the imputed values vector.
    names(impute_values) = colnames(data[non_skipped_vars])

    if (all_vars) {
      # We need to save imputation info for every variable, even if it has no
      # missing data.

      # Loop over all variables except exclusions.
      loop_over = which(non_skipped_vars)
      names(loop_over) = colnames(data)[non_skipped_vars]

    } else {
      # Only save imputation info for variables with missing data.

      # Loop over only variables with missing data.
      loop_over = any_nas
    }

    # Calculate number of NAs in advance.
    # benchmark comparison in tests/performance/perf-impute_missing_values.R
    sum_nas = sapply(loop_over, function(col_i) sum(is.na(data[[col_i]])))

    # Use double brackets rather than [, i] to support tibbles.
    col_classes = sapply(loop_over, function(col_i) class(data[[col_i]]))

    # TODO: vectorize, and support parallelization.
    #lapply(any_nas, function(i) {
    for (i in loop_over) {
      # Slightly aroundabout because any_nas contains column indices.
      colname = names(loop_over)[loop_over == i]

      nas = sum_nas[colname]
      col_class = col_classes[colname]

      if (verbose) {
        cat("Imputing", colname, paste0("(", i, " ", col_class, ")"),
            "with", prettyNum(nas, big.mark = ","), "NAs.")
      }

      if (colname %in% names(values)) {
        impute_value = values[[colname]]
        if (verbose) {
          cat(" Pre-filled.")
        }
      } else if (col_class %in% c("factor")) {
        # Impute factors to the mode.
        # Choose the first mode in case of ties.
        impute_value = Mode(data[[i]])[1]
      } else if (col_class %in% c("integer", "numeric", "logical", "labelled")) {
        # Impute numeric values to the median.
        impute_value = median(data[[i]], na.rm = T)
      } else {
        warning(paste(colname,
                      "should be numeric or factor type. But its class is",
                      col_class))
      }

      if (verbose) {
        cat(" Impute value:", impute_value, "\n")
      }

      # TODO: separate function to generate imputation values.
      impute_values[[colname]] = impute_value

      # Nothing to impute, continue to next column.
      if (nas == nrow(data)) {
        if (verbose) {
          cat("Note: cannot impute", colname, "because all values are NA.\n")
        }
        # TODO: return columns that are all NA.
        next
      } else if (nas == 0) {
        # Skip, there are no missing values for this var.
        next
      } else {
        # Make the imputation.
        new_data[is.na(data[[i]]), i] = impute_value
      }

    }

    if (!all_vars) {
      # If we're only saving imputation values for some variables, explicitly
      # remove any imputation values that were not calculated.
      impute_values = impute_values[names(any_nas)]
    }

    results$impute_values = impute_values

  } else if (type == "knn") {
    impute_info = caret::preProcess(new_data, method = c("knnImpute"))
    new_data = predict(impute_info, new_data)
    results$impute_info = impute_info

  }

  if (add_indicators) {
    # Append indicators.
    if (verbose) {
      cat("Generating missingness indicators.\n")
    }

    # Create missingness indicators from original dataframe.
    # This already incorporates the skip_vars argument via "any_nas".
    missing_indicators =
      missingness_indicators(data[, any_nas], prefix = prefix,
                             remove_constant = remove_constant,
                             remove_collinear = remove_collinear,
                             verbose = verbose)

    if (verbose) {
      cat("Indicators added:", ncol(missing_indicators), "\n")
    }

    new_data = cbind(new_data, missing_indicators)
  }

  results$data = new_data

  results

}
