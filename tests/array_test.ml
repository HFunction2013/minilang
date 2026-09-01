func main() {
    var arr = [10, 20, 30, 40, 50];
    println len(arr);
    println arr[0];
    println arr[4];
    arr[2] = 999;
    println arr[2];

    var s = "hello";
    println len(s);
    println charAt(s, 1);
    println substr(s, 1, 3);

    var sum = 0;
    var i = 0;
    while (i < len(arr)) {
        sum = sum + arr[i];
        i = i + 1;
    }
    print "sum = ";
    println sum;

    var n = toInt("123");
    println n;
    var t = toString(456);
    println t;
    println strcmp("abc", "abc");
    println strcmp("abc", "abd");

    return 0;
}
