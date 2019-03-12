func code<A>(f: () -> A) -> A {
    return f()
}

func timestamp() -> Int64 {
    return Int64(NSDate().timeIntervalSince1970 * 1000)
}
