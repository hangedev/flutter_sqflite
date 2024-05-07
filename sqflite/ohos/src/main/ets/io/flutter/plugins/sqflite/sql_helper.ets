/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

export class SqlHelper {
  /// 分离sql的属性部分
  public static getSqlDataName(jsonStr: string): string[] {
    // 提取属性部分
    // let pattern = new RegExp('INSERT INTO (\\w+) \\(([^()]+)\\)');
    let pattern = new RegExp('INSERT OR REPLACE INTO (\\w+) \\(([^()]+)\\)');
    const propertiesMatch = pattern.exec(jsonStr);
    const propertiesStr = propertiesMatch ? propertiesMatch[2] : ''; // 提取属性部分的字符串
    const properties = propertiesStr.split(',').map(prop => prop.trim()); // 将属性部分字符串拆分为数组
    return properties;
  }

  /// 分离sql的值部分
  public static getSqlData(jsonStr: string): string[] {
    // 提取值部分
    const valuesRegex = '/VALUES \(([^)]+)\)/'; // 匹配VALUES括号内的值部分
    const valuesMatch = jsonStr.match(valuesRegex);
    const valuesStr = valuesMatch ? valuesMatch[1] : ''; // 提取值部分的字符串
    const values = valuesStr.split(',')
      .map(val => val.trim())
      .map(val => val.replace('/\?/g', '')); // 将值部分字符串拆分为数组，并去掉问号
    return values;
  }

  /// 分离sql的表名部分
  public static getInsertSqlTableName(jsonStr: string): string {
    // 提取表名
    let firstMatch: number = jsonStr.search('INSERT OR REPLACE INTO');
    let pattern: RegExp;
    if (firstMatch >= 0) {
      pattern = new RegExp('INSERT OR REPLACE INTO (\\w+) \\(([^()]+)\\)');
    }else {
      pattern = new RegExp('INSERT INTO (\\w+)');
    }
    // let pattern = new RegExp('INSERT INTO (\\w+) \\(([^()]+)\\)');
    const propertiesMatch = pattern.exec(jsonStr);
    const propertiesStr = propertiesMatch ? propertiesMatch[1] : ''; // 提取属性部分的字符串
    return propertiesStr;
  }

  /// 分离sql的表名部分
  public static getQuerySqlTableName(jsonStr: string): string {
    // 提取表名
    let pattern = new RegExp("FROM\\s+(\\w+)")
    let match = pattern.exec(jsonStr)
    if (match == null) return '';
    return match[1];
  }

  /// 分离sql的Where部分
  public static getQuerySqlWhereName(jsonStr: string): string[] {

    // 提取表名
    let pattern = new RegExp("SELECT \\* FROM (\\w+) WHERE (\\w+ = \\?)(?: AND (\\w+ = \\?))*")
    let match = pattern.exec(jsonStr)
    if (match == null) return [];
    const whereClauses: string[] = match.slice(2).filter((clause: string) => clause !== undefined);

    const whereColumns: string[] = whereClauses.filter((clause) => clause.includes('='))
      .map((clause) => clause.split('=')[0].trim());
    return whereColumns;
  }

  /// 分离sql的SELECT部分
  public static getQuerySqlSELECTName(jsonStr: string): string[] {
    // 提取SELECT后面的参数
    const selectParamsRegex = '/SELECT\s+([^\s]+)\s+FROM/'; // 正则表达式匹配SELECT和FROM之间的参数
    const selectParamsMatch = jsonStr.match(selectParamsRegex);
    const selectParams = selectParamsMatch ? selectParamsMatch[1].split(',') : []; // 将参数按逗号分隔成数组
    return selectParams;
  }

  /// 分离sql的表名部分
  public static getUpdateSqlTableName(jsonStr: string): string {
    let firstMatch:number = jsonStr.search('UPDATE');
    let pattern: RegExp;
    if (firstMatch >= 0) {
      pattern = new RegExp('UPDATE\\s+(\\w+)');
    }else {
      pattern = new RegExp('DELETE FROM\\s+(\\w+)');
    }

    let match = pattern.exec(jsonStr);
    if (match == null) return '';
    return match[1];
  }

  /// 分离sql的Where部分
  public static getUpdateSqlWhereName(jsonStr: string): string[] {
    // 提取WHERE后面的参数
    const wherePattern: RegExp = new RegExp('WHERE\\s+([^]+?)\\s*$'); // 匹配WHERE后面的值
    const whereMatch = jsonStr.match(wherePattern);
    if (whereMatch == null) return [];
    const whereValues = whereMatch[1].split(',').map((clause) => clause.split('=')[0].trim());
    return whereValues;
  }

  /// 分离sql的SELECT部分
  public static getUpdateSqlSETName(jsonStr: string): string[] {
    // 提取SET后面的参数
    const setPattern: RegExp = new RegExp('SET +([^]+?) +WHERE'); // 匹配SET后面的值
    const setMatch = jsonStr.match(setPattern);
    if (setMatch == null) return [];
    const setValues = setMatch[1].split(',').map((clause) => clause.split('=')[0].trim());
    return setValues;
  }

  /// 分离sql的表名部分
  public static getDeleteSqlTableName(jsonStr: string): string {
    // 提取表名
    let pattern = new RegExp("DELETE FROM (\\w+)");
    let match = pattern.exec(jsonStr);
    if (match == null) return '';
    return match[1];
  }

  /// 分离sql的Where部分
  public static getDeleteSqlWhereName(jsonStr: string): string[] {
    // 提取WHERE后面的参数
    const wherePattern: RegExp = new RegExp('WHERE +([^]+?) *$'); // 匹配WHERE后面的值
    const whereMatch = jsonStr.match(wherePattern);
    if (whereMatch == null) return [];
    const whereValues = whereMatch[1].split(',').map((clause) => clause.split('=')[0].trim());
    return whereValues;
  }

  /// 获取数据库路径上的最后一项作为数据库名
  public static getLastPathName(path: string): string {
    // 通过split方法将路径分割成数组
    const pathParts = path.split('/');

    // 获取最后一个元素
    return pathParts[pathParts.length - 1];
  }

  /// map转化为json
  public static mapToJson(jsonStr: Map<string, Object>): string {
    if (jsonStr.size <= 0) return '{}';
    let result: string = '{';
    jsonStr.forEach((value, key) => {
      result += key + ":" + value.toString() + ",";
    })
    // 可以选择去掉最后一个逗号
    // result = result.slice(0, -1);
    result += '}';
    return result;
  }

  // /// json转化为map
  // public static parseJsonString(jsonStr: string): Map<string, string> {
  //   // 去除字符串两端的空格
  //   jsonStr = jsonStr.trim();
  //
  //   // 检查字符串是否以 '{' 开头和以 '}' 结尾
  //   if (jsonStr[0] !== '{' || jsonStr[jsonStr.length - 1] !== '}') {
  //     throw new Error('Invalid JSON string format');
  //   }
  //
  //   // 创建一个空的Map对象
  //   const map = new Map<string, string>();
  //
  //   // 去除首尾的 {} 后，将字符串按 ',' 分割为键值对数组
  //   const keyValuePairs = jsonStr.slice(1, -1).split(',');
  //
  //   // 遍历键值对数组
  //   for (const keyValuePair of keyValuePairs) {
  //     // 使用 ':' 分割键和值
  //     const list: Array<string> = keyValuePair.split(':');
  //
  //     // 去除键和值两端的空格
  //     // const trimmedKey = list[0].trim();
  //     // const trimmedValue = list[1].trim();
  //
  //     // 将键和值添加到Map中
  //     if (list[0] != '') {
  //       map.set(list[0], list[1]);
  //     }
  //   }
  //   return map;
  // }

  /// 获取map的keys
  // public static getMapKeys(jsonStr: Map<string, Object>): string {
  //   let result: string = '';
  //   jsonStr.forEach((value, key) => {
  //     result += key + ', ';
  //   })
  //   result = result.slice(0, result.length - 2);
  //   return result;
  // }

  /// 获取map的values
  // public static getMapValues(jsonStr: Map<string, Object>): string {
  //   let result: string = '';
  //   jsonStr.forEach((value, key) => {
  //     result += value + ', ';
  //   })
  //   result = result.slice(0, result.length - 2);
  //   return result;
  // }
}