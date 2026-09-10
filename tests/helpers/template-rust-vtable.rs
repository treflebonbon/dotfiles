// Minimized safe-code reproducer for the Rust 1.98.0 vtable miscompilation:
// https://github.com/rust-lang/rust/issues/161441#issuecomment-5381883955
use std::marker::PhantomData;

struct MyError;

trait StreamingBody {
    type BodyError;
}
struct Body;
impl StreamingBody for Body {
    type BodyError = MyError;
}

trait Service {
    type Output;
}
struct HttpClientService;
impl Service for HttpClientService {
    type Output = Body;
}

trait Trait {
    fn method(&self);
}
impl<F, R, ResBody> Trait for (F, PhantomData<R>)
where
    F: Fn() -> R,
    HttpClientService: Service<Output = ResBody>,
    ResBody: StreamingBody<BodyError: Sized>,
{
    fn method(&self) {}
}

async fn inspect_websocket_message() {}

fn main() {
    (&(inspect_websocket_message, PhantomData) as &dyn Trait).method();
    println!("done");
}
