package main

import (
	"fmt"
	"net/http"
)

func healthHandler(writer http.ResponseWriter, request *http.Request) {
	if request.URL.Path != "/" {
		http.NotFound(writer, request)
		return
	}

	writer.WriteHeader(http.StatusOK)
	_, _ = fmt.Fprintln(writer, "OK")
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", healthHandler)

	if err := http.ListenAndServe(":8080", mux); err != nil {
		panic(err)
	}
}
