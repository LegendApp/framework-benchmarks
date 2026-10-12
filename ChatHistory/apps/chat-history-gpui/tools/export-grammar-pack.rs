fn main() {
    let path = std::env::args().nth(1).expect("output syntax pack path");
    syntect::dumps::dump_to_file(&two_face::syntax::extra_newlines(), path)
        .expect("write syntect grammar pack");
}
