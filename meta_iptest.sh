#!/bin/bash

# 默认最大并行进程数、输入文件和输出文件
max_parallel=100
input_file="ip.txt"
output_file="realip.txt"
csv_file="realip.csv"

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -mp)
            if [[ -n $2 && $2 =~ ^[0-9]+$ ]]; then
                max_parallel=$2
                shift 2
            else
                echo "Error: -mp requires a valid number argument"
                exit 1
            fi
            ;;
        -i)
            if [[ -n $2 ]]; then
                input_file=$2
                shift 2
            else
                echo "Error: -i requires a valid file path"
                exit 1
            fi
            ;;
        -o)
            if [[ -n $2 ]]; then
                output_file=$2
                shift 2
            else
                echo "Error: -o requires a valid file path"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 [-mp max_parallel] [-i input_file] [-o output_file]"
            exit 1
            ;;
    esac
done

# 清空输出文件，并在CSV文件中添加列说明
> $output_file
echo "ip,port,rtt" > $csv_file  # 添加CSV列说明

# 测试函数
test_ip() {
    ip=$1
    port=$2

    result=$(curl -A "trace" --ssl-no-revoke --resolve cf-ns.com:$port:$ip https://cf-ns.com:$port/cdn-cgi/trace -s --connect-timeout 2 --max-time 10 | grep "uag")

    if [[ $result == *"uag=trace"* ]]; then
        echo "$ip:$port" >> $output_file
        echo "Success: $ip:$port"
        # 调用第二次测试
        second_test_ip "$ip" "$port"
  #  else
   #     echo "Failed: $ip:$port"
    fi
}

# 第二次测试函数，输出到CSV文件
second_test_ip() {
    ip=$1
    port=$2

    # 执行第二次测试并提取延迟
    latency=$(curl -A "trace" --ssl-no-revoke --retry 2 --resolve cf-ns.com:$port:$ip https://cf-ns.com:$port/cdn-cgi/trace -s --connect-timeout 2 --max-time 3 -w "timems=%{time_connect}" | grep -o 'timems=[0-9.]*')

    # 如果找到延迟，将结果写入CSV文件
    if [[ $latency == timems=* ]]; then
        latency_value=${latency#timems=}
        echo "$ip,$port,$latency_value" >> $csv_file
        echo "Latency: $ip:$port = $latency_value ms"
   # else
       # echo "Latency test failed for $ip:$port"
    fi
}

# 读取指定的输入文件中的每一行
while IFS=: read -r ip port; do
    # 调用测试函数并在后台执行
    test_ip "$ip" "$port" &

    # 增加并行进程计数
    current_jobs=$((current_jobs + 1))

    # 如果当前并行进程达到最大限制，等待所有进程完成
    if (( current_jobs >= max_parallel )); then
        wait
        current_jobs=0
    fi
done < "$input_file"

# 等待所有后台进程完成
wait

# 对 CSV 文件按第三列 (rtt) 进行排序，并输出到同一个文件
sort -t, -k3 -n $csv_file -o $csv_file
