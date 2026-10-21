#include <assert.h>
#include "../OriginalPort/ios/render_scale.h"
int main(void) {
    assert(ChuzzleRenderScale(320,480)==1);
    assert(ChuzzleRenderScale(1206,2622)==4);
    assert(ChuzzleRenderScale(2064,2752)==6);
    assert(ChuzzleRenderScale(2048,2732)==6);
    assert(ChuzzleRenderScale(2400,3200)==7);
    assert(ChuzzleRenderScale(0,0)==1);
    assert(ChuzzleRenderScale(100000,100000)==8);
}
