#' @title Count the terminal nodes in each tree from a random forest
#'
#' @description
#' Returns a vector of terminal node counts for each tree in a random forest.
#' The distribution of terminal node counts is helpful when seeking to optimize
#' the maxnodes hyperparameter of the random forest. By default RF allows very
#' large trees, which may result in overfitting. Optimizing the number of
#' terminal nodes in a random forest is a more direct way of requiring simpler
#' trees than the minimum node size hyperparameter.
#'
#' @param rf Random Forest object
#'
#' @return vector of terminal node counts
#'
#' @examples
#'
#' library(SuperLearner)
#' library(ck37r)
#'
#' data(Boston, package = "MASS")
#'
#' set.seed(1)
#'
#' # Downsample to 100 observations speed up example.
#' Boston = Boston[sample(nrow(Boston), 100L), ]
#'
#' sl = SuperLearner(Boston$medv, subset(Boston, select = -medv),
#'                   family = gaussian(),
#'                   cvControl = list(V = 3),
#'                   SL.library = c("SL.mean", "SL.glm", "SL.randomForest"))
#'
#' sl
#'
#' summary(rf_count_terminal_nodes(sl$fitLibrary$SL.randomForest_All$object))
#'
#' max_terminal_nodes =
#'        max(rf_count_terminal_nodes(sl$fitLibrary$SL.randomForest_All$object))
#'
#' max_terminal_nodes
#'
#' # Now run create.Learner() based on that maximum.
#'
#' # It is often handy to convert to log scale of a hyperparameter before
#' # testing a ~linear grid.
#' # NOTE: -0.7 ~ 0.69 ~ log(0.5) which is the multiplier that yields sqrt(max)
#' maxnode_seq = unique(round(exp(log(max_terminal_nodes) *
#'                                exp(c(-0.97, -0.7, -0.45, -0.15, 0)))))
#' maxnode_seq
#'
#' rf = SuperLearner::create.Learner("SL.randomForest", detailed_names = TRUE,
#'                                   name_prefix = "rf",
#'                                   # fewer trees for testing speed only.
#'                                   params = list(ntree = 100),
#'                                   tune = list(maxnodes = maxnode_seq))
#'
#' sl = SuperLearner(Boston$medv, subset(Boston, select = -medv),
#'                   family = gaussian(),
#'                   cvControl = list(V = 3),
#'                   SL.library = c("SL.mean", "SL.glm", rf$names))
#'
#' sl
#'
#' @seealso \code{\link[randomForest]{getTree}}
#'    \code{\link[randomForest]{randomForest}}
#'
#' @references
#'
#' Breiman, L. (2001). Random forests. Machine learning, 45(1), 5-32.
#'
#' @export
#'
#' @importFrom randomForest getTree
rf_count_terminal_nodes = function(rf) {
  terminal_nodes = rep(NA, rf$forest$ntree)

  # TODO: vectorize
  for (tree_i in 1:rf$forest$ntree) {
    # Extract a single tree from the forest.
    tree = randomForest::getTree(rf, tree_i, labelVar = F)

    # Terminal nodes have 0 as their split variable.
    # NOTE: if we turn labelVar on, split variables with have NAs instead of 0s.
    sum_na = sum(tree[, "split var"] == 0)

    terminal_nodes[tree_i] = sum_na
  }

  return(terminal_nodes)
}
