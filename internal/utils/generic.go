package utils

import "golang.org/x/exp/constraints"

// MergeMaps merges two or more maps together, into single map.
func MergeMaps[M ~map[K]V, K comparable, V any](maps ...M) M {
	merged := make(M)
	for _, m := range maps {
		for k, v := range m {
			merged[k] = v
		}
	}
	return merged
}

// Into traverse the elements in k and calls the supplied function f to
// convert them into elements if type V.
func Into[K, V any](k []K, f func(k K) *V) []*V {
	result := make([]*V, 0, len(k))
	for _, k := range k {
		if v := f(k); v != nil {
			result = append(result, v)
		}
	}
	return result
}

func Sum[M ~map[K]V, K comparable, V constraints.Integer | constraints.Float](m M) int {
	var out int
	for _, v := range m {
		out += int(v)
	}
	return out
}
