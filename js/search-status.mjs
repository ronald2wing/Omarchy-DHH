// Search status copy: the results' status line, while loading, while searching and for each response.

// While the dataset is still loading, and while a search is under way.
export const LOADING_TEXT = "Loading posts…"
export const SEARCHING_TEXT = "Searching…"

// What the results show for one search response (search.mjs search):
//   text            the status line
//   needsFiller     nothing matched, so random posts fill the results
//                   under the no-results line, as x.com does
//   highlightQuery  what the rows highlight: the corrected query when the
//                   worker corrected a typo ("omarcy" -> "omarchy", which the
//                   line names too), else the query as typed
// `query` is the query as typed; `maxResults` is the cap the search ran with.
export function describeResponse(response, query, maxResults) {
  const results = response.results || []
  const correctedQuery = String(response.correctedQuery || "")
  const shownCorrection = correctedQuery.trim()
  const total = typeof response.total === "number" ? response.total : results.length
  const countText = response.capped ? maxResults + "+" : String(total)
  const highlightQuery = correctedQuery || query
  let text = ""
  if (correctedQuery && response.closeMatches) text = "Close matches for “" + shownCorrection + "”"
  else if (correctedQuery) text = "Showing results for “" + shownCorrection + "” · " + countText
  else if (response.closeMatches) text = "No exact results · close matches"
  else if (response.capped) text = maxResults + "+ results"
  else if (total > 0) text = total + " result" + (total === 1 ? "" : "s")
  else return { text: "No results for “" + query + "”", needsFiller: true, highlightQuery: highlightQuery }
  return { text: text, needsFiller: false, highlightQuery: highlightQuery }
}
