// Package untidy requires a module that it does not import, so that the lint action fails.
package untidy

// Value returns one.
func Value() int {
	return 1
}
