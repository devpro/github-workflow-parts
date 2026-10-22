// Package untidy requires a module it never imports, which go mod tidy would take out and the lint action fails on.
package untidy

// Value returns one.
func Value() int {
	return 1
}
