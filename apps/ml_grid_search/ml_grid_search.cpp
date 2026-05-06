#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

#if defined(__has_include)
#  if __has_include("boinc_api.h")
#    include "boinc_api.h"
#    define HAVE_BOINC_API 1
#  else
#    define HAVE_BOINC_API 0
#  endif
#else
#  define HAVE_BOINC_API 0
#endif

static std::string trim(const std::string& s) {
    size_t a = 0;
    while (a < s.size() && std::isspace(static_cast<unsigned char>(s[a]))) a++;
    size_t b = s.size();
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) b--;
    return s.substr(a, b - a);
}

static std::map<std::string, std::string> read_kv_file(const std::string& path) {
    std::ifstream in(path);
    if (!in) {
        std::cerr << "ml_grid_search: can't open input file: " << path << "\n";
        std::exit(1);
    }
    std::map<std::string, std::string> kv;
    std::string line;
    while (std::getline(in, line)) {
        line = trim(line);
        if (line.empty() || line.rfind("#", 0) == 0) continue;
        auto pos = line.find('=');
        if (pos == std::string::npos) continue;
        std::string key = trim(line.substr(0, pos));
        std::string val = trim(line.substr(pos + 1));
        if (!key.empty()) kv[key] = val;
    }
    return kv;
}

// simple deterministic RNG (LCG)
struct LcgRng {
    uint64_t state;
    explicit LcgRng(uint64_t seed) : state(seed ? seed : 1) {}
    uint32_t next_u32() {
        state = state * 6364136223846793005ULL + 1ULL;
        return static_cast<uint32_t>(state >> 32);
    }
    double next_uniform() {  // [0, 1)
        return (next_u32() / 4294967296.0);
    }
};

static std::vector<double> make_dataset_x(int n) {
    std::vector<double> xs;
    xs.reserve(n);
    for (int i = 0; i < n; i++) {
        double t = (n == 1) ? 0.0 : (static_cast<double>(i) / (n - 1));
        // [-5, 5]
        xs.push_back(-5.0 + 10.0 * t);
    }
    return xs;
}

static std::vector<double> make_dataset_y(const std::vector<double>& xs, uint64_t seed) {
    // y = 2*x + 1 + noise
    LcgRng rng(seed);
    std::vector<double> ys;
    ys.reserve(xs.size());
    for (double x : xs) {
        double noise = (rng.next_uniform() - 0.5) * 0.5;  // [-0.25, 0.25)
        ys.push_back(2.0 * x + 1.0 + noise);
    }
    return ys;
}

static void ridge_fit_2d(
    const std::vector<double>& xs,
    const std::vector<double>& ys,
    double lambda,
    double& w0,
    double& w1
) {
    // X = [1, x]
    // Solve (X^T X + lambda*I) w = X^T y
    // (regularize both terms for simplicity)
    double s00 = 0, s01 = 0, s11 = 0;
    double b0 = 0, b1 = 0;
    for (size_t i = 0; i < xs.size(); i++) {
        double x = xs[i];
        double y = ys[i];
        s00 += 1.0;
        s01 += x;
        s11 += x * x;
        b0 += y;
        b1 += x * y;
    }
    s00 += lambda;
    s11 += lambda;
    double det = s00 * s11 - s01 * s01;
    if (std::fabs(det) < 1e-12) {
        w0 = 0;
        w1 = 0;
        return;
    }
    w0 = (b0 * s11 - b1 * s01) / det;
    w1 = (s00 * b1 - s01 * b0) / det;
}

static double mse(const std::vector<double>& xs, const std::vector<double>& ys, double w0, double w1) {
    double acc = 0;
    for (size_t i = 0; i < xs.size(); i++) {
        double pred = w0 + w1 * xs[i];
        double e = pred - ys[i];
        acc += e * e;
    }
    return acc / (xs.empty() ? 1.0 : static_cast<double>(xs.size()));
}

int main(int argc, char** argv) {
#if HAVE_BOINC_API
    boinc_init();
#endif

    std::string in_path = "in";
    std::string out_path = "out";
    if (argc >= 2) in_path = argv[1];
    if (argc >= 3) out_path = argv[2];

#if HAVE_BOINC_API
    {
        char resolved[1024];
        int rc = boinc_resolve_filename(in_path.c_str(), resolved, sizeof(resolved));
        if (rc) {
            std::cerr << "ml_grid_search: boinc_resolve_filename(in) failed: " << rc << "\n";
            boinc_finish(1);
        }
        in_path = resolved;
        rc = boinc_resolve_filename(out_path.c_str(), resolved, sizeof(resolved));
        if (rc) {
            std::cerr << "ml_grid_search: boinc_resolve_filename(out) failed: " << rc << "\n";
            boinc_finish(1);
        }
        out_path = resolved;
    }
#endif

    auto kv = read_kv_file(in_path);
    double lambda = 0.1;
    uint64_t seed = 42;
    if (kv.count("lambda")) lambda = std::stod(kv["lambda"]);
    if (kv.count("seed")) seed = static_cast<uint64_t>(std::stoull(kv["seed"]));
    int n = 50;
    if (kv.count("n")) n = std::stoi(kv["n"]);
    if (n <= 1) n = 2;

    auto xs = make_dataset_x(n);
    auto ys = make_dataset_y(xs, seed);

    double w0 = 0, w1 = 0;
    ridge_fit_2d(xs, ys, lambda, w0, w1);
    double loss = mse(xs, ys, w0, w1);

    std::ofstream out(out_path, std::ios::out | std::ios::trunc);
    if (!out) {
        std::cerr << "ml_grid_search: can't open output file: " << out_path << "\n";
        return 1;
    }

    out << std::fixed << std::setprecision(8);
    out << "{";
    out << "\"lambda\":" << lambda << ",";
    out << "\"seed\":" << seed << ",";
    out << "\"n\":" << n << ",";
    out << "\"mse\":" << loss << ",";
    out << "\"w0\":" << w0 << ",";
    out << "\"w1\":" << w1;
    out << "}\n";
    out.flush();
    out.close();

    std::cerr << "ml_grid_search: done; lambda=" << lambda << " mse=" << loss << "\n";
#if HAVE_BOINC_API
    boinc_finish(0);
#endif
    return 0;
}
