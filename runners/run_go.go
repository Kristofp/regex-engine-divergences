package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
)

type Entry struct {
	ID       string `json:"id"`
	Pattern  string `json:"pattern"`
	TestText string `json:"testText"`
	Flags    string `json:"flags"`
}

type Match struct {
	MatchText string `json:"match"`
	Index     int    `json:"index"`
}

type Result struct {
	Matches []Match `json:"matches"`
	Error   *string `json:"error"`
}

func main() {
	data, _ := io.ReadAll(os.Stdin)
	var entries []Entry
	json.Unmarshal(data, &entries)
	results := make(map[string]Result)

	for _, e := range entries {
		func() {
			defer func() {
				if r := recover(); r != nil {
					s := fmt.Sprintf("%v", r)
					results[e.ID] = Result{Matches: []Match{}, Error: &s}
				}
			}()
			p := e.Pattern
			var prefix string
			if strings.Contains(e.Flags, "i") {
				prefix += "i"
			}
			if strings.Contains(e.Flags, "m") {
				prefix += "m"
			}
			if strings.Contains(e.Flags, "s") {
				prefix += "s"
			}
			// Go-specific `U` flag — swap greedy/lazy default.
			// `(?U)x*` behaves like `x*?`. Other engines don't
			// have this. Needed so flag-matrix tests for Go pass.
			if strings.Contains(e.Flags, "U") {
				prefix += "U"
			}
			if prefix != "" {
				p = "(?" + prefix + ")" + p
			}
			rx, err := regexp.Compile(p)
			if err != nil {
				s := err.Error()
				results[e.ID] = Result{Matches: []Match{}, Error: &s}
				return
			}
			// Always emit all matches regardless of 'g' flag — see docs/v1-corpus-fix-spec.md
			// and matches the bridge's behavior.
			locs := rx.FindAllStringIndex(e.TestText, -1)
			matches := make([]Match, 0, len(locs))
			for _, loc := range locs {
				matches = append(matches, Match{
					MatchText: e.TestText[loc[0]:loc[1]],
					Index:     loc[0],
				})
			}
			results[e.ID] = Result{Matches: matches, Error: nil}
		}()
	}

	out, _ := json.Marshal(results)
	os.Stdout.Write(out)
}
